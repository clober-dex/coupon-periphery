// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ICouponOracle} from "../interfaces/ICouponOracle.sol";

contract MockRouter is Ownable2Step, Initializable {
    ICouponOracle public immutable oracle;

    constructor(ICouponOracle _oracle) Ownable(msg.sender) {
        oracle = _oracle;
    }

    function initialize() external initializer {
        _transferOwnership(msg.sender);
    }

    receive() external payable {}

    function swap(address tokenIn, address tokenOut, uint256 amountIn) external {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        uint8 decimalsIn = IERC20Metadata(tokenIn).decimals();
        uint8 decimalsOut = IERC20Metadata(tokenOut).decimals();
        uint256 amountOut;
        if (decimalsIn > decimalsOut) {
            amountOut = amountIn * oracle.getAssetPrice(tokenIn) / oracle.getAssetPrice(tokenOut)
                / 10 ** (decimalsIn - decimalsOut);
        } else {
            amountOut = amountIn * 10 ** (decimalsOut - decimalsIn) * oracle.getAssetPrice(tokenIn)
                / oracle.getAssetPrice(tokenOut);
        }
        IERC20(tokenOut).transfer(msg.sender, amountOut);
    }
}
