// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../mocks/MockToken.sol";
import "../../../contracts/SimpleSubstitute.sol";

contract SimpleSubstituteUnitTest is Test {
    MockToken public token;
    SimpleSubstitute public substitute;

    function setUp() public {
        token = new MockToken("Mock", "MCK", 18);
        substitute = new SimpleSubstitute(address(token), address(this), address(this));

        token.mint(address(this), 1000000000 ether);
        token.approve(address(substitute), type(uint256).max);
    }

    function testMint() public {
        token.approve(address(substitute), 100);
        substitute.mint(100, address(this));
        assertEq(substitute.balanceOf(address(this)), 100);
        assertEq(token.balanceOf(address(substitute)), 100);
    }

    function testBurn() public {
        substitute.mint(100, address(this));
        substitute.burn(100, address(this));
        assertEq(substitute.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(substitute)), 0);
    }

    function testClaim() public {
        vm.expectRevert("Not implemented");
        substitute.claim();
    }

    function testSetTreasury() public {
        vm.expectEmit(address(substitute));
        emit ISubstitute.SetTreasury(address(0x123));
        substitute.setTreasury(address(0x123));
        assertEq(substitute.treasury(), address(0x123));
    }

    function testSetTreasuryOwnership() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, (address(12341234))));
        vm.prank(address(12341234));
        substitute.setTreasury(address(0x123));
    }

    function testWithdrawLostToken() public {
        MockToken lostToken = new MockToken("Lost", "LST", 18);
        lostToken.mint(address(substitute), 100);
        substitute.withdrawLostToken(address(lostToken), address(this));
        assertEq(lostToken.balanceOf(address(this)), 100);
        assertEq(lostToken.balanceOf(address(substitute)), 0);
    }

    function testWithdrawLostTokenWithUnderlyingToken() public {
        substitute.mint(1000, address(this));

        token.mint(address(substitute), 100);
        substitute.withdrawLostToken(address(token), address(0x123));
        assertEq(token.balanceOf(address(0x123)), 100);
        assertEq(token.balanceOf(address(substitute)), 1000);
    }

    function testWithdrawLostTokenOwnership() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, (address(12341234))));
        vm.prank(address(12341234));
        substitute.withdrawLostToken(address(0x123), address(0x123));
    }
}
