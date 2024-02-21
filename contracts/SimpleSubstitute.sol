// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ISubstitute} from "./interfaces/ISubstitute.sol";

contract SimpleSubstitute is ISubstitute, ERC20Permit, Ownable2Step {
    using SafeERC20 for IERC20;

    address public immutable override underlyingToken;
    uint8 private immutable _decimals;

    address public override treasury;

    constructor(string memory name_, string memory symbol_, address underlyingToken_, address treasury_, address owner_)
        ERC20Permit(name_)
        ERC20(name_, symbol_)
        Ownable(owner_)
    {
        underlyingToken = underlyingToken_;
        _decimals = IERC20Metadata(underlyingToken_).decimals();
        treasury = treasury_;
        emit SetTreasury(treasury_);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mintableAmount() external pure returns (uint256) {
        return type(uint256).max;
    }

    function burnableAmount() external view returns (uint256) {
        return totalSupply();
    }

    function mint(uint256 amount, address to) external {
        IERC20(underlyingToken).safeTransferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
    }

    function burn(uint256 amount, address to) external {
        _burn(msg.sender, amount);
        IERC20(underlyingToken).safeTransfer(to, amount);
    }

    function claim() external pure {
        revert("Not implemented");
    }

    function setTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
        emit SetTreasury(newTreasury);
    }

    function withdrawLostToken(address token, address recipient) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (token == underlyingToken) {
            balance -= totalSupply();
        }
        if (balance > 0) {
            IERC20(token).safeTransfer(recipient, balance);
        }
    }
}
