// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {CouponKey} from "../libraries/CouponKey.sol";
import {PermitSignature} from "../libraries/PermitParams.sol";

interface ICouponMarketRouter {
    struct MarketSellParams {
        address market;
        uint64 deadline;
        uint16 limitPriceIndex;
        address recipient;
        uint64 minRawAmount;
        CouponKey couponKey;
        uint256 amount;
    }

    error InvalidAccess();
    error InvalidMarket();
    error Deadline();
    error FailedToSendValue();

    function marketSellCoupons(MarketSellParams calldata params, PermitSignature calldata couponPermitParams)
        external;

    function batchMarketSellCoupons(MarketSellParams[] calldata paramsList, PermitSignature calldata couponPermitParams)
        external;
}
