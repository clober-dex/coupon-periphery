// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ISubstitute} from "./ISubstitute.sol";
import {ERC20PermitParams} from "../libraries/PermitParams.sol";

interface IEthSubstituteMinter {
    error ExceedsAmount();

    function mint(ERC20PermitParams calldata permitParams, ISubstitute substitute, uint256 amount, address recipient)
        external
        payable;
}
