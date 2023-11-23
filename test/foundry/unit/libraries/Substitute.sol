// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Constants} from "../../Constants.sol";
import {ISubstitute} from "../../../../contracts/interfaces/ISubstitute.sol";
import {SubstituteLibrary} from "../../../../contracts/libraries/Substitute.sol";
import {IWETH9} from "../../../../contracts/external/weth/IWETH9.sol";
import {ForkUtils} from "../../Utils.sol";

contract SubstituteLibraryUnitTest is Test {
    address public weth;
    address public waweth;

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);
        weth = Constants.WETH;
        waweth = Constants.COUPON_WETH_SUBSTITUTE;
        vm.deal(address(this), 1000 ether);
        IWETH9(weth).deposit{value: 1000 ether}();
        IERC20(weth).approve(address(waweth), type(uint256).max);
    }

    function testEnsureThisBalance() public {
        _testEnsureThisBalance(
            Input({substitute: 1 ether, underlying: 1 ether, ensure: 0 ether}),
            Expected({thisSubstitute: 0, thisUnderlying: 0, wrapperSubstitute: 0, wrapperUnderlying: 0})
        );
        _testEnsureThisBalance(
            Input({substitute: 1 ether, underlying: 1 ether, ensure: 0.5 ether}),
            Expected({thisSubstitute: 0, thisUnderlying: 0, wrapperSubstitute: 0, wrapperUnderlying: 0})
        );
        _testEnsureThisBalance(
            Input({substitute: 1 ether, underlying: 1 ether, ensure: 1 ether}),
            Expected({thisSubstitute: 0, thisUnderlying: 0, wrapperSubstitute: 0, wrapperUnderlying: 0})
        );
        _testEnsureThisBalance(
            Input({substitute: 1 ether, underlying: 1 ether, ensure: 1.5 ether}),
            Expected({thisSubstitute: 0, thisUnderlying: 0, wrapperSubstitute: 0.5 ether, wrapperUnderlying: -0.5 ether})
        );
        _testEnsureThisBalance(
            Input({substitute: 1 ether, underlying: 1 ether, ensure: 2 ether}),
            Expected({thisSubstitute: 0, thisUnderlying: 0, wrapperSubstitute: 1 ether, wrapperUnderlying: -1 ether})
        );
        _testEnsureThisBalance(
            Input({substitute: 1 ether, underlying: 1 ether, ensure: 2.3 ether}),
            Expected({
                thisSubstitute: 0,
                thisUnderlying: -0.3 ether,
                wrapperSubstitute: 1.3 ether,
                wrapperUnderlying: -1 ether
            })
        );
    }

    struct Input {
        uint256 substitute;
        uint256 underlying;
        uint256 ensure;
    }

    struct Expected {
        int256 thisSubstitute;
        int256 thisUnderlying;
        int256 wrapperSubstitute;
        int256 wrapperUnderlying;
    }

    function _testEnsureThisBalance(Input memory input, Expected memory expected) internal {
        SubstituteLibraryWrapper wrapper = new SubstituteLibraryWrapper();
        IERC20(weth).approve(address(wrapper), type(uint256).max);

        ISubstitute(waweth).mint(input.substitute, address(wrapper));
        IERC20(weth).transfer(address(wrapper), input.underlying);

        int256 beforeThisSubstitute = int256(IERC20(waweth).balanceOf(address(this)));
        int256 beforeThisUnderlying = int256(IERC20(weth).balanceOf(address(this)));
        int256 beforeWrapperSubstitute = int256(IERC20(waweth).balanceOf(address(wrapper)));
        int256 beforeWrapperUnderlying = int256(IERC20(weth).balanceOf(address(wrapper)));

        wrapper.ensureThisBalance(waweth, address(this), input.ensure);

        int256 afterThisSubstitute = int256(IERC20(waweth).balanceOf(address(this)));
        int256 afterThisUnderlying = int256(IERC20(weth).balanceOf(address(this)));
        int256 afterWrapperSubstitute = int256(IERC20(waweth).balanceOf(address(wrapper)));
        int256 afterWrapperUnderlying = int256(IERC20(weth).balanceOf(address(wrapper)));

        assertEq(afterThisSubstitute - beforeThisSubstitute, expected.thisSubstitute, "THIS_SUBSTITUTE");
        assertEq(afterThisUnderlying - beforeThisUnderlying, expected.thisUnderlying, "THIS_UNDERLYING");
        assertEq(afterWrapperSubstitute - beforeWrapperSubstitute, expected.wrapperSubstitute, "WRAPPER_SUBSTITUTE");
        assertEq(afterWrapperUnderlying - beforeWrapperUnderlying, expected.wrapperUnderlying, "WRAPPER_UNDERLYING");
    }
}

contract SubstituteLibraryWrapper {
    function ensureThisBalance(address substitute, address payer, uint256 amount) external {
        SubstituteLibrary.ensureThisBalance(ISubstitute(substitute), payer, amount);
    }
}
