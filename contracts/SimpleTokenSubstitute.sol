// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IWETH9} from "./external/weth/IWETH9.sol";
import {ISubstitute} from "./interfaces/ISubstitute.sol";

contract SimpleTokenSubstitute is ISubstitute, ERC20Permit, Ownable2Step {
    error UnsupportedFunction();

    using SafeERC20 for IERC20;

    uint256 public constant SUPPLY_BUFFER = 10 ** 24; // 0.1%

    IWETH9 private immutable _weth;
    uint8 private immutable _decimals;
    address public immutable override underlyingToken;

    address public override treasury;

    constructor(address weth_, address asset_, address treasury_, address owner_)
        ERC20Permit(string.concat("Wrapped ", IERC20Metadata(asset_).name()))
        ERC20(string.concat("Wrapped ", IERC20Metadata(asset_).name()), string.concat("W", IERC20Metadata(asset_).symbol()))
        Ownable(owner_)
    {
        _weth = IWETH9(weth_);
        _decimals = IERC20Metadata(asset_).decimals();
        underlyingToken = asset_;
        treasury = treasury_;
        emit SetTreasury(treasury_);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(uint256 amount, address to) external {
        IERC20(underlyingToken).safeTransferFrom(msg.sender, address(this), amount);

        _mint(to, amount);
    }

    function mintableAmount() external pure returns (uint256) {
        return type(uint256).max;
    }

    function burn(uint256 amount, address to) external {
        _burn(msg.sender, amount);

        if (underlyingToken == address(_weth)) {
            _weth.withdraw(amount);
            (bool success,) = payable(to).call{value: amount}("");
            if (!success) revert ValueTransferFailed();
        } else {
            IERC20(underlyingToken).safeTransfer(address(to), amount);
        }
    }

    function burnableAmount() external pure returns (uint256) {
        return type(uint256).max;
    }

    function setTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
        emit SetTreasury(newTreasury);
    }

    function claim() external pure {
        revert UnsupportedFunction();
    }

    function withdrawLostToken(address token, address recipient) external onlyOwner {
        if (token == underlyingToken) {
            revert InvalidToken();
        }
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(recipient, balance);
        }
    }

    receive() external payable {}
}
