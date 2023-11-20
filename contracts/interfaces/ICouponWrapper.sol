// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ERC20PermitParams, PermitSignature} from "../libraries/PermitParams.sol";
import {Coupon} from "../libraries/Coupon.sol";
import {CouponKey} from "../libraries/CouponKey.sol";

interface ICouponWrapper {
    function getWrappedCoupon(CouponKey calldata couponKey) external view returns (address wrappedCoupon);

    function getWrappedCoupons(CouponKey[] calldata couponKeys)
        external
        view
        returns (address[] memory wrappedCoupons);

    function buildMetadata(CouponKey calldata couponKey) external view returns (bytes memory metadata);

    function buildBatchMetadata(CouponKey[] calldata couponKeys) external view returns (bytes memory metadata);

    function wrap(Coupon[] calldata coupons, address recipient) external;

    function wrapWithPermit(
        PermitSignature calldata couponPermitSignature,
        Coupon[] calldata coupons,
        address recipient
    ) external;

    function unwrap(Coupon[] calldata coupons, address recipient) external;
}
