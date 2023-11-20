// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISubstitute} from "../interfaces/ISubstitute.sol";

library SubstituteLibrary {
    using SafeERC20 for IERC20;

    function ensureThisBalance(ISubstitute substitute, address payer, uint256 amount) internal {
        uint256 balance = IERC20(address(substitute)).balanceOf(address(this));
        if (balance >= amount) {
            return;
        }
        unchecked {
            amount -= balance;
        }

        address underlyingToken = substitute.underlyingToken();
        uint256 underlyingBalance = IERC20(underlyingToken).balanceOf(address(this));
        if (underlyingBalance < amount) {
            IERC20(underlyingToken).safeTransferFrom(payer, address(this), amount - underlyingBalance);
        }
        IERC20(underlyingToken).approve(address(substitute), amount);
        substitute.mint(amount, address(this));
    }
}
