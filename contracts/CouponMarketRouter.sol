// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {CloberOrderBook} from "./external/clober/CloberOrderBook.sol";
import {CloberMarketSwapCallbackReceiver} from "./external/clober/CloberMarketSwapCallbackReceiver.sol";
import {CloberMarketFactory} from "./external/clober/CloberMarketFactory.sol";
import {IWrapped1155Factory} from "./external/wrapped1155/IWrapped1155Factory.sol";
import {ICouponManager} from "./interfaces/ICouponManager.sol";
import {ICouponWrapper} from "./interfaces/ICouponWrapper.sol";
import {ISubstitute} from "./interfaces/ISubstitute.sol";
import {ICouponMarketRouter} from "./interfaces/ICouponMarketRouter.sol";
import {CouponKeyLibrary, CouponKey} from "./libraries/CouponKey.sol";
import {PermitParamsLibrary, PermitSignature} from "./libraries/PermitParams.sol";
import {Wrapped1155MetadataBuilder} from "./libraries/Wrapped1155MetadataBuilder.sol";

contract CouponMarketRouter is CloberMarketSwapCallbackReceiver, ICouponMarketRouter {
    using SafeERC20 for IERC20;
    using CouponKeyLibrary for CouponKey;
    using PermitParamsLibrary for *;

    IWrapped1155Factory internal immutable _wrapped1155Factory;
    ICouponManager internal immutable _couponManager;
    ICouponWrapper internal immutable _couponWrapper;
    CloberMarketFactory private immutable _cloberMarketFactory;

    modifier checkDeadline(uint64 deadline) {
        _checkDeadline(deadline);
        _;
    }

    function _checkDeadline(uint64 deadline) internal view {
        if (block.timestamp > deadline) {
            revert Deadline();
        }
    }

    constructor(address wrapped1155Factory, address cloberMarketFactory, address couponManager, address couponWrapper) {
        _wrapped1155Factory = IWrapped1155Factory(wrapped1155Factory);
        _cloberMarketFactory = CloberMarketFactory(cloberMarketFactory);
        _couponManager = ICouponManager(couponManager);
        _couponWrapper = ICouponWrapper(couponWrapper);
    }

    function cloberMarketSwapCallback(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        bytes calldata data
    ) external payable {
        if (_cloberMarketFactory.getMarketHost(msg.sender) == address(0)) {
            revert InvalidAccess();
        }
        (address payer, address recipient, CouponKey memory couponKey) = abi.decode(data, (address, address, CouponKey));
        bytes memory metadata = Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKey);
        uint256 couponId = couponKey.toId();
        if (inputToken != _wrapped1155Factory.getWrapped1155(address(_couponManager), couponId, metadata)) {
            revert InvalidMarket();
        }

        uint256 erc20Amount =
            Math.min(IERC20(inputToken).balanceOf(payer), IERC20(inputToken).allowance(payer, address(this)));

        if (inputAmount > erc20Amount) {
            _couponManager.safeTransferFrom(
                payer, address(_wrapped1155Factory), couponId, inputAmount - erc20Amount, metadata
            );
            IERC20(inputToken).safeTransfer(msg.sender, inputAmount - erc20Amount);
        } else {
            erc20Amount = inputAmount;
        }
        IERC20(inputToken).safeTransferFrom(payer, msg.sender, erc20Amount);

        ISubstitute(outputToken).burn(outputAmount, recipient);
    }

    function marketSellCoupons(MarketSellParams calldata params, PermitSignature calldata couponPermitParams)
        external
    {
        couponPermitParams.tryPermitERC1155(_couponManager, msg.sender, address(this), true);

        _marketSellCoupon(params);
    }

    function batchMarketSellCoupons(MarketSellParams[] calldata paramsList, PermitSignature calldata couponPermitParams)
        external
    {
        couponPermitParams.tryPermitERC1155(_couponManager, msg.sender, address(this), true);

        for (uint256 i; i < paramsList.length; ++i) {
            _marketSellCoupon(paramsList[i]);
        }
    }

    function _marketSellCoupon(MarketSellParams calldata params) internal checkDeadline(params.deadline) {
        bytes memory data = abi.encode(msg.sender, params.recipient, params.couponKey);
        CloberOrderBook(params.market).marketOrder(
            address(this),
            params.limitPriceIndex,
            params.minRawAmount,
            params.amount,
            2, // ask, expendInput
            data
        );
    }
}
