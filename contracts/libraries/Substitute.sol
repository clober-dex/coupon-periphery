// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISubstitute} from "../interfaces/ISubstitute.sol";

library SubstituteLibrary {
    using SafeERC20 for IERC20;

    function mintAll(ISubstitute substitute, address payer, uint256 minRequiredBalance) internal {
        address underlyingToken = substitute.underlyingToken();
        uint256 thisBalance = IERC20(address(substitute)).balanceOf(address(this));
        uint256 underlyingBalance = IERC20(underlyingToken).balanceOf(address(this));
        if (minRequiredBalance > thisBalance + underlyingBalance) {
            unchecked {
                IERC20(underlyingToken).safeTransferFrom(
                    payer, address(this), minRequiredBalance - thisBalance - underlyingBalance
                );
                underlyingBalance = minRequiredBalance - thisBalance;
            }
        }
        if (underlyingBalance > 0) {
            IERC20(underlyingToken).approve(address(substitute), underlyingBalance);
            substitute.mint(underlyingBalance, address(this));
        }
    }

    function burnAll(ISubstitute substitute, address to) internal {
        uint256 leftAmount = IERC20(address(substitute)).balanceOf(address(this));
        if (leftAmount > 0) {
            ISubstitute(substitute).burn(leftAmount, to);
        }
    }
}
