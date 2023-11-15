// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import "../../contracts/Greeter.sol";

contract GreeterTest is Test {
    Greeter public greeter;

    function setUp() public {
        greeter = new Greeter("TEST");
    }

    function testSetGreeting(string memory _greeting) public {
        greeter.setGreeting(_greeting);
        assertEq(_greeting, greeter.greet());
    }
}
