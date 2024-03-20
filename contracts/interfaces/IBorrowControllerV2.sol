// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IControllerV2} from "./IControllerV2.sol";
import {ERC20PermitParams, PermitSignature} from "../libraries/PermitParams.sol";
import {Epoch} from "../libraries/Epoch.sol";

interface IBorrowControllerV2 is IControllerV2 {
    event SwapToken(
        uint256 indexed positionId,
        address indexed inToken,
        address indexed outToken,
        uint256 inAmount,
        uint256 outAmount
    );

    struct SwapParams {
        address inSubstitute;
        uint256 amount;
        bytes data;
    }

    error CollateralSwapFailed(string reason);

    function borrow(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 debtAmount,
        int256 maxPayInterest,
        Epoch expiredWith,
        SwapParams calldata swapParams,
        ERC20PermitParams calldata collateralPermitParams
    ) external payable returns (uint256 positionId);

    function adjust(
        uint256 positionId,
        uint256 collateralAmount,
        uint256 debtAmount,
        int256 interestThreshold,
        Epoch expiredWith,
        SwapParams calldata swapParams,
        PermitSignature calldata positionPermitParams,
        ERC20PermitParams calldata collateralPermitParams,
        ERC20PermitParams calldata debtPermitParams
    ) external payable;
}
