// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICouponManager} from "./interfaces/ICouponManager.sol";
import {ICouponWrapper} from "./interfaces/ICouponWrapper.sol";
import {IWrapped1155Factory} from "./external/wrapped1155/IWrapped1155Factory.sol";
import {CouponLibrary, Coupon} from "./libraries/Coupon.sol";
import {CouponKeyLibrary, CouponKey} from "./libraries/CouponKey.sol";
import {PermitParamsLibrary, ERC20PermitParams, PermitSignature} from "./libraries/PermitParams.sol";
import {Wrapped1155MetadataBuilder} from "./libraries/Wrapped1155MetadataBuilder.sol";

contract CouponWrapper is ICouponWrapper {
    using SafeERC20 for IERC20;
    using CouponLibrary for Coupon;
    using CouponKeyLibrary for CouponKey;
    using PermitParamsLibrary for *;

    ICouponManager private immutable _couponManager;
    IWrapped1155Factory private immutable _wrapped1155Factory;

    constructor(address couponManager_, address wrapped1155Factory_) {
        _couponManager = ICouponManager(couponManager_);
        _wrapped1155Factory = IWrapped1155Factory(wrapped1155Factory_);
    }

    function getWrappedCoupon(CouponKey calldata couponKey) external view returns (address) {
        return _wrapped1155Factory.getWrapped1155(
            address(_couponManager), couponKey.toId(), Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKey)
        );
    }

    function getWrappedCoupons(CouponKey[] calldata couponKeys)
        external
        view
        returns (address[] memory wrappedCoupons)
    {
        wrappedCoupons = new address[](couponKeys.length);
        for (uint256 i; i < couponKeys.length; ++i) {
            wrappedCoupons[i] = _wrapped1155Factory.getWrapped1155(
                address(_couponManager),
                couponKeys[i].toId(),
                Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKeys[i])
            );
        }
    }

    function buildMetadata(CouponKey calldata couponKey) external view returns (bytes memory) {
        return Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKey);
    }

    function buildBatchMetadata(CouponKey[] calldata couponKeys) external view returns (bytes memory) {
        return Wrapped1155MetadataBuilder.buildWrapped1155BatchMetadata(couponKeys);
    }

    function wrap(Coupon[] calldata coupons, address recipient) external {
        _wrap(coupons, recipient);
    }

    function wrapWithPermit(
        PermitSignature calldata couponPermitSignature,
        Coupon[] calldata coupons,
        address recipient
    ) external {
        couponPermitSignature.tryPermitERC1155(_couponManager, msg.sender, address(this), true);
        _wrap(coupons, recipient);
    }

    function _wrap(Coupon[] calldata coupons, address recipient) internal {
        bytes memory batchMetadata;
        address[] memory wrappedCoupons = new address[](coupons.length);
        for (uint256 i; i < coupons.length; ++i) {
            bytes memory metadata = Wrapped1155MetadataBuilder.buildWrapped1155Metadata(coupons[i].key);
            wrappedCoupons[i] = _wrapped1155Factory.getWrapped1155(address(_couponManager), coupons[i].id(), metadata);
            batchMetadata = bytes.concat(batchMetadata, metadata);
        }

        _couponManager.safeBatchTransferFrom(msg.sender, address(_wrapped1155Factory), coupons, batchMetadata);

        for (uint256 i; i < coupons.length; ++i) {
            IERC20(wrappedCoupons[i]).safeTransfer(recipient, coupons[i].amount);
        }
    }

    function unwrap(Coupon[] calldata coupons, address recipient) external {
        bytes memory batchMetadata;
        uint256[] memory tokenIds = new uint256[](coupons.length);
        uint256[] memory amounts = new uint256[](coupons.length);
        for (uint256 i; i < coupons.length; ++i) {
            bytes memory metadata = Wrapped1155MetadataBuilder.buildWrapped1155Metadata(coupons[i].key);
            address token = _wrapped1155Factory.getWrapped1155(address(_couponManager), coupons[i].id(), metadata);

            IERC20(token).safeTransferFrom(msg.sender, address(this), coupons[i].amount);
            batchMetadata = bytes.concat(batchMetadata, metadata);
            tokenIds[i] = coupons[i].id();
            amounts[i] = coupons[i].amount;
        }

        _wrapped1155Factory.batchUnwrap(address(_couponManager), tokenIds, amounts, recipient, batchMetadata);
    }
}
