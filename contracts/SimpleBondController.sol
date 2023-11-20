// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {ISimpleBondController} from "./interfaces/ISimpleBondController.sol";
import {IPositionLocker} from "./interfaces/IPositionLocker.sol";
import {ICouponManager} from "./interfaces/ICouponManager.sol";
import {IBondPositionManager} from "./interfaces/IBondPositionManager.sol";
import {ICouponWrapper} from "./interfaces/ICouponWrapper.sol";
import {ISubstitute} from "./interfaces/ISubstitute.sol";
import {Epoch} from "./libraries/Epoch.sol";
import {Coupon} from "./libraries/Coupon.sol";
import {Wrapped1155MetadataBuilder} from "./libraries/Wrapped1155MetadataBuilder.sol";
import {PermitParamsLibrary, ERC20PermitParams, PermitSignature} from "./libraries/PermitParams.sol";
import {SubstituteLibrary} from "./libraries/Substitute.sol";
import {IWETH9} from "./external/weth/IWETH9.sol";

contract SimpleBondController is IPositionLocker, ERC1155Holder, ISimpleBondController, Ownable2Step {
    using SubstituteLibrary for ISubstitute;
    using PermitParamsLibrary for *;
    using SafeERC20 for IERC20;

    IWETH9 private immutable _weth;
    IBondPositionManager private immutable _bondPositionManager;
    ICouponManager private immutable _couponManager;
    ICouponWrapper private immutable _couponWrapper;

    constructor(
        address weth_,
        address bondPositionManager_,
        address couponManager_,
        address couponWrapper_,
        address owner_
    ) Ownable(owner_) {
        _weth = IWETH9(weth_);
        _bondPositionManager = IBondPositionManager(bondPositionManager_);
        _couponManager = ICouponManager(couponManager_);
        _couponWrapper = ICouponWrapper(couponWrapper_);
        _couponManager.setApprovalForAll(address(_couponWrapper), true);
    }

    function positionLockAcquired(bytes calldata data) external returns (bytes memory result) {
        if (msg.sender != address(_bondPositionManager)) revert InvalidAccess();
        (address user, uint256 tokenId, uint256 amount, Epoch expiredWith, bool wrapCoupons, address asset) =
            abi.decode(data, (address, uint256, uint256, Epoch, bool, address));
        if (tokenId == 0) {
            tokenId = _bondPositionManager.mint(asset);
            result = abi.encode(tokenId);
        }
        (Coupon[] memory couponsToMint, Coupon[] memory couponsToBurn, int256 amountDelta) =
            _bondPositionManager.adjustPosition(tokenId, amount, expiredWith);
        if (amountDelta > 0) {
            ISubstitute(asset).ensureThisBalance(user, uint256(amountDelta));
            IERC20(asset).approve(address(_bondPositionManager), uint256(amountDelta));
            _bondPositionManager.depositToken(address(asset), uint256(amountDelta));
        } else if (amountDelta < 0) {
            _bondPositionManager.withdrawToken(asset, address(this), uint256(-amountDelta));
            ISubstitute(asset).burn(uint256(-amountDelta), user);
        }
        if (couponsToMint.length > 0) {
            if (wrapCoupons) {
                _bondPositionManager.mintCoupons(couponsToMint, address(this), "");
                _couponWrapper.wrap(couponsToMint, user);
            } else {
                _bondPositionManager.mintCoupons(couponsToMint, user, "");
            }
        }
        if (couponsToBurn.length > 0) {
            _couponManager.safeBatchTransferFrom(user, address(this), couponsToBurn, "");
            _bondPositionManager.burnCoupons(couponsToBurn);
        }

        _bondPositionManager.settlePosition(tokenId);
    }

    function mint(ERC20PermitParams calldata permitParams, address asset, uint256 amount, Epoch expiredWith)
        external
        payable
        returns (uint256)
    {
        return _mint(permitParams, asset, amount, expiredWith, false);
    }

    function mintAndWrapCoupons(
        ERC20PermitParams calldata permitParams,
        address asset,
        uint256 amount,
        Epoch expiredWith
    ) external payable returns (uint256) {
        return _mint(permitParams, asset, amount, expiredWith, true);
    }

    function _mint(
        ERC20PermitParams calldata permitParams,
        address asset,
        uint256 amount,
        Epoch expiredWith,
        bool wrapCoupons
    ) internal returns (uint256 positionId) {
        address underlyingToken = ISubstitute(asset).underlyingToken();
        _checkEth(underlyingToken);
        permitParams.tryPermit(underlyingToken, msg.sender, address(this));
        bytes memory result =
            _bondPositionManager.lock(abi.encode(msg.sender, 0, amount, expiredWith, wrapCoupons, asset));
        positionId = abi.decode(result, (uint256));
        _bondPositionManager.transferFrom(address(this), msg.sender, positionId);
    }

    function adjust(
        ERC20PermitParams calldata tokenPermitParams,
        PermitSignature calldata positionPermitParams,
        PermitSignature calldata couponPermitParams,
        uint256 tokenId,
        uint256 amount,
        Epoch expiredWith
    ) external payable {
        _adjust(tokenPermitParams, positionPermitParams, couponPermitParams, tokenId, amount, expiredWith, false);
    }

    function adjustAndWrapCoupons(
        ERC20PermitParams calldata tokenPermitParams,
        PermitSignature calldata positionPermitParams,
        PermitSignature calldata couponPermitParams,
        uint256 tokenId,
        uint256 amount,
        Epoch expiredWith
    ) external payable {
        _adjust(tokenPermitParams, positionPermitParams, couponPermitParams, tokenId, amount, expiredWith, true);
    }

    function _adjust(
        ERC20PermitParams calldata tokenPermitParams,
        PermitSignature calldata positionPermitParams,
        PermitSignature calldata couponPermitParams,
        uint256 tokenId,
        uint256 amount,
        Epoch expiredWith,
        bool wrapCoupons
    ) internal {
        positionPermitParams.tryPermitERC721(_bondPositionManager, tokenId, address(this));
        couponPermitParams.tryPermitERC1155(_couponManager, msg.sender, address(this), true);
        address asset = _bondPositionManager.getPosition(tokenId).asset;
        address underlyingToken = ISubstitute(asset).underlyingToken();
        _checkEth(underlyingToken);
        tokenPermitParams.tryPermit(underlyingToken, msg.sender, address(this));

        _bondPositionManager.lock(abi.encode(msg.sender, tokenId, amount, expiredWith, wrapCoupons, asset));
    }

    function _checkEth(address underlyingToken) internal {
        if (underlyingToken != address(_weth) && msg.value > 0) {
            revert InvalidValueTransfer();
        } else if (msg.value > 0) {
            _weth.deposit{value: msg.value}();
        }
    }

    function withdrawLostToken(address token, address to) external onlyOwner {
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
    }
}
