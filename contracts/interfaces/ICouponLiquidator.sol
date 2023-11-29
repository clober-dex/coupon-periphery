// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ERC20PermitParams} from "../libraries/PermitParams.sol";

interface ICouponLiquidator {
    error CollateralSwapFailed(string reason);
    error UnsupportedLiquidationType();

    enum LiquidationType {
        WithRouter,
        WithOwnLiquidity
    }

    function liquidateWithRouter(uint256 positionId, uint256 swapAmount, bytes calldata swapData, address recipient)
        external;

    function liquidateWithOwnLiquidity(
        ERC20PermitParams calldata debtPermitParams,
        uint256 positionId,
        uint256 maxRepayAmount,
        address recipient
    ) external payable;
}
