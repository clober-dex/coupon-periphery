// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {CloberMarketSwapCallbackReceiver} from "../external/clober/CloberMarketSwapCallbackReceiver.sol";
import {IWETH9} from "../external/weth/IWETH9.sol";
import {IWrapped1155Factory} from "../external/wrapped1155/IWrapped1155Factory.sol";
import {CloberOrderBook} from "../external/clober/CloberOrderBook.sol";
import {ICouponManager} from "../interfaces/ICouponManager.sol";
import {Coupon, CouponLibrary} from "./Coupon.sol";
import {CouponKey, CouponKeyLibrary} from "./CouponKey.sol";
import {Wrapped1155MetadataBuilder} from "./Wrapped1155MetadataBuilder.sol";
import {IERC721Permit} from "../interfaces/IERC721Permit.sol";
import {ISubstitute} from "../interfaces/ISubstitute.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {IController} from "../external/clober-v2/IController.sol";
import {IBookManager} from "../external/clober-v2/IBookManager.sol";
import {BookId, BookIdLibrary} from "../external/clober-v2/BookId.sol";
import {CurrencyLibrary, Currency} from "../external/clober-v2/Currency.sol";
import {IControllerV2} from "../interfaces/IControllerV2.sol";
import {SubstituteLibrary} from "./Substitute.sol";

import {Epoch} from "./Epoch.sol";

abstract contract ControllerV2 is IControllerV2, ERC1155Holder, Ownable2Step, ReentrancyGuard {
    using SafeCast for uint256;
    using BookIdLibrary for IBookManager.BookKey;
    using SafeERC20 for IERC20;
    using CouponKeyLibrary for CouponKey;
    using CouponLibrary for Coupon;
    using CurrencyLibrary for Currency;
    using SubstituteLibrary for ISubstitute;

    IWrapped1155Factory internal immutable _wrapped1155Factory;
    IController internal immutable _cloberController;
    ICouponManager internal immutable _couponManager;
    IBookManager internal immutable _bookManager;
    IWETH9 internal immutable _weth;

    mapping(uint256 couponId => IBookManager.BookKey) internal _couponSellMarkets;
    mapping(uint256 couponId => IBookManager.BookKey) internal _couponBuyMarkets;

    constructor(
        address wrapped1155Factory,
        address cloberController,
        address bookManager,
        address couponManager,
        address weth
    ) Ownable(msg.sender) {
        _wrapped1155Factory = IWrapped1155Factory(wrapped1155Factory);
        _cloberController = IController(cloberController);
        _couponManager = ICouponManager(couponManager);
        _bookManager = IBookManager(bookManager);

        _couponManager.setApprovalForAll(address(_cloberController), true);
        _weth = IWETH9(weth);
    }

    modifier wrapAndRefundETH() {
        bool hasMsgValue = address(this).balance > 0;
        if (hasMsgValue) _weth.deposit{value: address(this).balance}();
        _;
        if (hasMsgValue) {
            uint256 leftBalance = _weth.balanceOf(address(this));
            if (leftBalance > 0) {
                _weth.withdraw(leftBalance);
                (bool success,) = msg.sender.call{value: leftBalance}("");
                require(success);
            }
        }
    }

    function _executeCouponTrade(
        address user,
        address token,
        Coupon[] memory couponsToMint,
        Coupon[] memory couponsToBurn,
        int256 interestThreshold
    ) internal {
        uint256 length = couponsToBurn.length + couponsToMint.length;
        IController.Action[] memory actionList = new IController.Action[](length);
        bytes[] memory paramsDataList = new bytes[](length);
        address[] memory tokensToSettle = new address[](length + 1);
        tokensToSettle[length] = token;
        IController.ERC20PermitParams[] memory erc20PermitParamsList;
        IController.ERC721PermitParams[] memory erc721PermitParamsList;

        uint256 amount;

        length = couponsToBurn.length;
        for (uint256 i = 0; i < length; ++i) {
            actionList[i] = IController.Action.TAKE;
            IBookManager.BookKey memory key = _couponBuyMarkets[couponsToBurn[i].key.toId()];
            tokensToSettle[i] = Currency.unwrap(key.base);
            amount += couponsToBurn[i].amount;
            paramsDataList[i] = abi.encode(
                IController.TakeOrderParams({
                    id: key.toId(),
                    limitPrice: type(uint256).max,
                    quoteAmount: couponsToBurn[i].amount,
                    hookData: ""
                })
            );
        }
        if (amount > 0) IERC20(token).approve(address(_cloberController), amount);

        length = couponsToMint.length;
        for (uint256 i = 0; i < length; ++i) {
            actionList[couponsToBurn.length + i] = IController.Action.SPEND;
            IBookManager.BookKey memory key = _couponSellMarkets[couponsToMint[i].key.toId()];
            tokensToSettle[couponsToBurn.length + i] = Currency.unwrap(key.base);
            amount = couponsToMint[i].amount;
            paramsDataList[couponsToBurn.length + i] = abi.encode(
                IController.SpendOrderParams({
                    id: key.toId(),
                    limitPrice: type(uint256).max,
                    baseAmount: amount,
                    hookData: ""
                })
            );
            // key.base can't be Currency.NATIVE
            IERC20(Currency.unwrap(key.base)).approve(address(_cloberController), amount);
        }

        if (interestThreshold > 0) {
            if (IERC20(token).balanceOf(address(this)) < uint256(interestThreshold)) _takeMaxToken(token, user);
            IERC20(token).approve(address(_cloberController), uint256(interestThreshold));
        }

        uint256 beforeBalance = IERC20(token).balanceOf(address(this));
        _cloberController.execute(
            actionList,
            paramsDataList,
            tokensToSettle,
            erc20PermitParamsList,
            erc721PermitParamsList,
            uint64(block.timestamp)
        );
        uint256 afterBalance = IERC20(token).balanceOf(address(this));
        int256 balanceDiff;
        unchecked {
            if (afterBalance > beforeBalance) {
                balanceDiff = -(afterBalance - beforeBalance).toInt256();
            } else {
                balanceDiff = (beforeBalance - afterBalance).toInt256();
            }
        }
        if (interestThreshold < balanceDiff) {
            revert ControllerSlippage();
        }
        emit CouponTrade(-balanceDiff, couponsToBurn, couponsToMint);
    }

    function _getUnderlyingToken(address substitute) internal view returns (address) {
        return ISubstitute(substitute).underlyingToken();
    }

    function _burnAllSubstitute(address substitute, address to) internal {
        uint256 leftAmount = IERC20(substitute).balanceOf(address(this));
        if (leftAmount == 0) return;
        ISubstitute(substitute).burn(leftAmount, to);
    }

    function _takeMaxToken(address token, address user) internal {
        address underlyingToken = ISubstitute(token).underlyingToken();
        uint256 amount =
            Math.min(IERC20(underlyingToken).allowance(user, address(this)), IERC20(underlyingToken).balanceOf(user));
        if (amount > 0) IERC20(underlyingToken).safeTransferFrom(user, address(this), amount);
        uint256 underlyingBalance = IERC20(underlyingToken).balanceOf(address(this));
        if (underlyingBalance > 0) {
            IERC20(underlyingToken).approve(token, underlyingBalance);
            ISubstitute(token).mint(underlyingBalance, address(this));
        }
    }

    function _ensureBalance(address token, address user, uint256 amount) internal {
        // TODO: consider to use SubstituteLibrary
        address underlyingToken = ISubstitute(token).underlyingToken();
        uint256 thisBalance = IERC20(token).balanceOf(address(this));
        uint256 underlyingBalance = IERC20(underlyingToken).balanceOf(address(this));
        if (amount > thisBalance + underlyingBalance) {
            unchecked {
                IERC20(underlyingToken).safeTransferFrom(user, address(this), amount - thisBalance - underlyingBalance);
                underlyingBalance = amount - thisBalance;
            }
        }
        if (underlyingBalance > 0) {
            IERC20(underlyingToken).approve(token, underlyingBalance);
            ISubstitute(token).mint(underlyingBalance, address(this));
        }
    }

    function _wrapCoupons(Coupon[] memory coupons) internal {
        // wrap 1155 to 20
        bytes memory metadata = Wrapped1155MetadataBuilder.buildWrapped1155BatchMetadata(coupons);
        _couponManager.safeBatchTransferFrom(address(this), address(_wrapped1155Factory), coupons, metadata);
    }

    function _unwrapCoupons(Coupon[] memory coupons) internal {
        uint256[] memory tokenIds = new uint256[](coupons.length);
        uint256[] memory amounts = new uint256[](coupons.length);
        unchecked {
            for (uint256 i = 0; i < coupons.length; ++i) {
                tokenIds[i] = coupons[i].id();
                amounts[i] = coupons[i].amount;
            }
        }
        bytes memory metadata = Wrapped1155MetadataBuilder.buildWrapped1155BatchMetadata(coupons);
        _wrapped1155Factory.batchUnwrap(address(_couponManager), tokenIds, amounts, address(this), metadata);
    }

    function getCouponMarket(CouponKey memory couponKey)
        external
        view
        returns (IBookManager.BookKey memory, IBookManager.BookKey memory)
    {
        return (_couponSellMarkets[couponKey.toId()], _couponBuyMarkets[couponKey.toId()]);
    }

    function setCouponBookKey(
        CouponKey memory couponKey,
        IBookManager.BookKey calldata sellBookKey,
        IBookManager.BookKey calldata buyBookKey
    ) public virtual onlyOwner {
        bytes memory metadata = Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKey);
        uint256 couponId = couponKey.toId();
        address wrappedCoupon = _wrapped1155Factory.getWrapped1155(address(_couponManager), couponId, metadata);

        BookId sellMarketBookId = sellBookKey.toId();
        BookId buyMarketBookId = buyBookKey.toId();
        if (
            _bookManager.getBookKey(sellMarketBookId).unit != sellBookKey.unit
                || _bookManager.getBookKey(buyMarketBookId).unit != buyBookKey.unit
                || Currency.unwrap(sellBookKey.base) != wrappedCoupon || Currency.unwrap(buyBookKey.quote) != wrappedCoupon
        ) {
            revert InvalidMarket();
        }

        _couponSellMarkets[couponId] = sellBookKey;
        _couponBuyMarkets[couponId] = buyBookKey;

        emit SetCouponMarket(couponKey.asset, couponKey.epoch, sellMarketBookId, buyMarketBookId);
    }

    receive() external payable {}
}
