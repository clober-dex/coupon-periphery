// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EthSubstituteWrapper} from "../../../contracts/EthSubstituteWrapper.sol";
import {ISubstitute} from "../../../contracts/interfaces/ISubstitute.sol";
import {Constants} from "../Constants.sol";
import {ForkUtils} from "../Utils.sol";

contract EthSubstituteWrapperIntegrationTest is Test {
    EthSubstituteWrapper public wrapper;

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);
        wrapper = new EthSubstituteWrapper(Constants.WETH);
    }

    function testWrap() public {
        vm.deal(address(this), 10 ether);
        address recipient = address(0x123);

        uint256 balanceBefore = address(this).balance;
        uint256 substituteBefore = IERC20(Constants.COUPON_WETH_SUBSTITUTE).balanceOf(recipient);

        wrapper.wrap{value: 1 ether}(ISubstitute(Constants.COUPON_WETH_SUBSTITUTE), recipient);

        uint256 balanceAfter = address(this).balance;
        uint256 substituteAfter = IERC20(Constants.COUPON_WETH_SUBSTITUTE).balanceOf(recipient);

        assertEq(balanceAfter, balanceBefore - 1 ether, "BALANCE");
        assertEq(substituteAfter, 1 ether + substituteBefore, "SUBSTITUTE");
    }
}
