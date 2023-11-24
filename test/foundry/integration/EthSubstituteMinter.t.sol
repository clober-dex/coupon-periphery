// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import {EthSubstituteMinter} from "../../../contracts/EthSubstituteMinter.sol";
import {IEthSubstituteMinter} from "../../../contracts/interfaces/IEthSubstituteMinter.sol";
import {ISubstitute} from "../../../contracts/interfaces/ISubstitute.sol";
import {ERC20PermitParams} from "../../../contracts/libraries/PermitParams.sol";
import {IWETH9} from "../../../contracts/external/weth/IWETH9.sol";
import {Constants} from "../Constants.sol";
import {ForkUtils, PermitSignLibrary} from "../Utils.sol";

contract EthSubstituteMinterIntegrationTest is Test {
    using PermitSignLibrary for Vm;

    IWETH9 public weth = IWETH9(Constants.WETH);
    EthSubstituteMinter public wrapper;
    address public user;
    address public recipient = address(0x123);

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);
        wrapper = new EthSubstituteMinter(Constants.WETH);
        user = vm.addr(1);

        vm.deal(user, 10 ether);
        vm.prank(user);
        weth.deposit{value: 5 ether}();
    }

    function testMint() public {
        vm.startPrank(user);

        uint256 balanceBefore = user.balance;
        uint256 wethBalanceBefore = weth.balanceOf(user);
        uint256 substituteBefore = IERC20(Constants.COUPON_WETH_SUBSTITUTE).balanceOf(recipient);

        wrapper.mint{value: 1 ether}(
            vm.signPermit(1, IERC20Permit(Constants.WETH), address(wrapper), 1 ether),
            ISubstitute(Constants.COUPON_WETH_SUBSTITUTE),
            2 ether,
            recipient
        );

        uint256 balanceAfter = user.balance;
        uint256 wethBalanceAfter = weth.balanceOf(user);
        uint256 substituteAfter = IERC20(Constants.COUPON_WETH_SUBSTITUTE).balanceOf(recipient);

        assertEq(balanceAfter, balanceBefore - 1 ether, "BALANCE");
        assertEq(wethBalanceAfter, wethBalanceBefore - 1 ether, "WETH_BALANCE");
        assertEq(substituteAfter, 2 ether + substituteBefore, "SUBSTITUTE");

        vm.stopPrank();
    }

    function testMintWithJustETH() public {
        vm.startPrank(user);

        uint256 balanceBefore = user.balance;
        uint256 wethBalanceBefore = weth.balanceOf(user);
        uint256 substituteBefore = IERC20(Constants.COUPON_WETH_SUBSTITUTE).balanceOf(recipient);

        wrapper.mint{value: 1 ether}(
            vm.signPermit(1, IERC20Permit(Constants.WETH), address(wrapper), 1 ether),
            ISubstitute(Constants.COUPON_WETH_SUBSTITUTE),
            1 ether,
            recipient
        );

        uint256 balanceAfter = user.balance;
        uint256 wethBalanceAfter = weth.balanceOf(user);
        uint256 substituteAfter = IERC20(Constants.COUPON_WETH_SUBSTITUTE).balanceOf(recipient);

        assertEq(balanceAfter, balanceBefore - 1 ether, "BALANCE");
        assertEq(wethBalanceAfter, wethBalanceBefore, "WETH_BALANCE");
        assertEq(substituteAfter, 1 ether + substituteBefore, "SUBSTITUTE");

        vm.stopPrank();
    }

    function testMintWithJustWETH() public {
        vm.startPrank(user);

        uint256 balanceBefore = user.balance;
        uint256 wethBalanceBefore = weth.balanceOf(user);
        uint256 substituteBefore = IERC20(Constants.COUPON_WETH_SUBSTITUTE).balanceOf(recipient);

        wrapper.mint(
            vm.signPermit(1, IERC20Permit(Constants.WETH), address(wrapper), 1 ether),
            ISubstitute(Constants.COUPON_WETH_SUBSTITUTE),
            1 ether,
            recipient
        );

        uint256 balanceAfter = user.balance;
        uint256 wethBalanceAfter = weth.balanceOf(user);
        uint256 substituteAfter = IERC20(Constants.COUPON_WETH_SUBSTITUTE).balanceOf(recipient);

        assertEq(balanceAfter, balanceBefore, "BALANCE");
        assertEq(wethBalanceAfter, wethBalanceBefore - 1 ether, "WETH_BALANCE");
        assertEq(substituteAfter, 1 ether + substituteBefore, "SUBSTITUTE");

        vm.stopPrank();
    }

    function testMintWhenMsgValueExceedsAmount() public {
        vm.startPrank(user);

        ERC20PermitParams memory permitParams =
            vm.signPermit(1, IERC20Permit(Constants.WETH), address(wrapper), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IEthSubstituteMinter.ExceedsAmount.selector));
        wrapper.mint{value: 1 ether + 1}(
            permitParams, ISubstitute(Constants.COUPON_WETH_SUBSTITUTE), 1 ether, recipient
        );

        vm.stopPrank();
    }
}
