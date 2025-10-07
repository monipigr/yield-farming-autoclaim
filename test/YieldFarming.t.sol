// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/YieldFarming.sol";
import "../src/MockToken.sol";

contract YieldFarmingTest is Test {
    YieldFarming public yieldFarming;
    MockToken public rewardToken;
    MockToken public stakingToken1;
    MockToken public stakingToken2;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    bytes32 public poolId1;
    bytes32 public poolId2;

    uint public constant INITAL_SUPPLY = 1000000 * 1e18;
    uint public constant REWARD_RATE = 1 * 10**16; // 0.01 tokens per second  

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy contracts
        rewardToken = new MockToken("Reward Token", "RWD", INITAL_SUPPLY);
        stakingToken1 = new MockToken("Staking Token 1", "STK1", INITAL_SUPPLY);
        stakingToken2 = new MockToken("Staking Token 2", "STK2", INITAL_SUPPLY);
        yieldFarming = new YieldFarming(address(rewardToken));

        // Transfer tokens to users
        stakingToken1.transfer(user1, 10000 * 10**18);
        stakingToken1.transfer(user2, 10000 * 10**18);
        stakingToken2.transfer(user1, 10000 * 10**18);
        stakingToken2.transfer(user3, 10000 * 10**18);

        // Transfer reward tokens to the farming pool
        rewardToken.transfer(address(yieldFarming), 500000 * 10**18);

        // Create pools
        poolId1 = yieldFarming.createPool(address(stakingToken1), REWARD_RATE);
        poolId2 = yieldFarming.createPool(address(stakingToken2), REWARD_RATE * 2);

        // Approve tokens
        vm.startPrank(user1);
        stakingToken1.approve(address(yieldFarming), type(uint256).max);
        stakingToken2.approve(address(yieldFarming), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        stakingToken1.approve(address(yieldFarming), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user3);
        stakingToken2.approve(address(yieldFarming), type(uint256).max);
        vm.stopPrank();
    }

}
