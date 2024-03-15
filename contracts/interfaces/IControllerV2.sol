// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Epoch} from "../libraries/Epoch.sol";
import {BookId} from "../external/clober-v2/BookId.sol";

interface IControllerV2 {
    event SetCouponMarket(address indexed asset, Epoch indexed epoch, BookId sellMarketBookId, BookId buyMarketBookId);

    error InvalidAccess();
    error InvalidMarket();
    error ControllerSlippage();
}
