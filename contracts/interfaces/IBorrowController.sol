// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IController} from "./IController.sol";
import {ERC20PermitParams, PermitSignature} from "../libraries/PermitParams.sol";
import {Epoch} from "../libraries/Epoch.sol";

interface IBorrowController is IController {
    error CollateralSwapFailed(string reason);
    error InvalidDebtAmount();

    function borrow(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 maxPayInterest,
        Epoch expiredWith,
        ERC20PermitParams calldata collateralPermitParams
    ) external payable;

    function adjustPosition(
        uint256 positionId,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 maxPayInterest,
        uint256 minEarnInterest,
        Epoch expiredWith,
        PermitSignature calldata positionPermitParams,
        ERC20PermitParams calldata collateralPermitParams,
        ERC20PermitParams calldata debtPermitParams
    ) external payable;
}
