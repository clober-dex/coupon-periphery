// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IEthSubstituteMinter} from "./interfaces/IEthSubstituteMinter.sol";
import {ISubstitute} from "./interfaces/ISubstitute.sol";
import {IWETH9} from "./external/weth/IWETH9.sol";
import {PermitParamsLibrary, ERC20PermitParams} from "./libraries/PermitParams.sol";

contract EthSubstituteMinter is IEthSubstituteMinter {
    using PermitParamsLibrary for ERC20PermitParams;

    IWETH9 private immutable _weth;

    constructor(address weth) {
        _weth = IWETH9(weth);
    }

    function mint(ERC20PermitParams calldata permitParams, ISubstitute substitute, uint256 amount, address recipient)
        external
        payable
    {
        permitParams.tryPermit(address(_weth), msg.sender, address(this));
        if (msg.value > amount) {
            revert ExceedsAmount();
        }
        if (msg.value < amount) {
            _weth.transferFrom(msg.sender, address(this), amount - msg.value);
        }
        if (msg.value > 0) {
            _weth.deposit{value: msg.value}();
        }
        _weth.approve(address(substitute), amount);
        substitute.mint(amount, recipient);
    }
}
