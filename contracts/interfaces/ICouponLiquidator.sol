// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ERC20PermitParams} from "../libraries/PermitParams.sol";

interface ICouponLiquidator {
    error CollateralSwapFailed(string reason);
    error ExceedsThreshold();
    error UnsupportedLiquidationType();

    enum LiquidationType {
        WithRouter,
        WithOwnLiquidity
    }

    struct LiquidateWithRouterParams {
        uint256 positionId;
        uint256 swapAmount;
        bytes swapData;
        address recipient;
    }

    function liquidateWithRouter(LiquidateWithRouterParams calldata params) external;

    struct LiquidateWithOwnLiquidityParams {
        uint256 positionId;
        uint256 maxRepayAmount;
        address recipient;
    }

    function liquidateWithOwnLiquidity(
        ERC20PermitParams calldata debtPermitParams,
        LiquidateWithOwnLiquidityParams calldata params
    ) external payable;
}
