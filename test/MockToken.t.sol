// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/YieldFarming.sol";
import "../src/MockToken.sol";

contract MockTokenTest is Test {
    MockToken public mockToken;

    address public owner;
    address public user1;


    uint public constant INITAL_SUPPLY = 1000000 * 1e18;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");

        // Deploy contract
        mockToken = new MockToken("Mock Token", "MKT", INITAL_SUPPLY);
    }

    function test_mint() public {
        uint256 amount = 100 * 1e18;
        vm.startPrank(owner);
        uint256 balanceBefore = mockToken.balanceOf(owner);
        mockToken.mint(owner, amount);
        uint256 balanceAfter = mockToken.balanceOf(owner);

        assertEq(balanceBefore + amount, balanceAfter);
    }

    function test_mint_revertIfNotOwner() public {
        vm.startPrank(user1);
        vm.expectRevert();
        mockToken.mint(user1, 100*1e18);
        vm.stopPrank();
    }

    function test_burn() public {
        uint256 amount = 10*1e18;
        uint256 burnedAmount = 1*1e18;
        mockToken.mint(user1, amount);

        uint256 balanceBefore = mockToken.balanceOf(user1);

        vm.startPrank(user1);
        mockToken.burn(burnedAmount);
        uint256 balanceAfter = mockToken.balanceOf(user1);

        assertEq(balanceBefore, balanceAfter + burnedAmount);
    }

    
}
