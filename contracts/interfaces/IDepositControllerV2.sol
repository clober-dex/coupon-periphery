// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IControllerV2} from "./IControllerV2.sol";
import {ERC20PermitParams, PermitSignature} from "../libraries/PermitParams.sol";
import {Epoch} from "../libraries/Epoch.sol";

interface IDepositControllerV2 is IControllerV2 {
    function deposit(
        address token,
        uint256 amount,
        Epoch expiredWith,
        int256 minEarnInterest,
        ERC20PermitParams calldata tokenPermitParams
    ) external payable returns (uint256 positionId);

    function adjust(
        uint256 positionId,
        uint256 amount,
        Epoch expiredWith,
        int256 interestThreshold,
        ERC20PermitParams calldata tokenPermitParams,
        PermitSignature calldata positionPermitParams
    ) external payable;
}
