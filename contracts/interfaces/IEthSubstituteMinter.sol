// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ISubstitute} from "./ISubstitute.sol";

interface IEthSubstituteMinter {
    function mint(ISubstitute substitute, address recipient) external payable;
}
