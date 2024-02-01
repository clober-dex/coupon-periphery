// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Epoch} from "../libraries/Epoch.sol";
import {CouponKey} from "../libraries/CouponKey.sol";

interface IController {
    event SetCouponMarket(address indexed asset, Epoch indexed epoch, address indexed cloberMarket);

    error InvalidAccess();
    error InvalidMarket();
    error ControllerSlippage();

    function getCouponMarket(CouponKey memory couponKey) external view returns (address);

    function setCouponMarket(CouponKey memory couponKey, address cloberMarket) external;
}
