// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ISubstitute} from "./interfaces/ISubstitute.sol";
import {IWETH9} from "./external/weth/IWETH9.sol";

contract EthSubstituteWrapper {
    IWETH9 private immutable _weth;

    constructor(address weth) {
        _weth = IWETH9(weth);
    }

    function wrap(ISubstitute substitute, address to) external payable {
        _weth.deposit{value: msg.value}();
        _weth.approve(address(substitute), msg.value);
        substitute.mint(msg.value, to);
    }
}
