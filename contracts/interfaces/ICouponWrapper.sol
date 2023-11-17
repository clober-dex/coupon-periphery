// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ERC20PermitParams, PermitSignature} from "../libraries/PermitParams.sol";
import {Coupon} from "../libraries/Coupon.sol";

interface ICouponWrapper {
    function wrap(Coupon[] calldata coupons, address recipient) external;

    function wrapWithPermit(
        PermitSignature calldata couponPermitSignature,
        Coupon[] calldata coupons,
        address recipient
    ) external;

    function unwrap(Coupon[] calldata coupons, address recipient) external;
}
