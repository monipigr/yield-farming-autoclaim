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

    function test_validTokenReward() public {
        vm.expectRevert("Invalid token reward");
        new YieldFarming(address(0));
    }

    function test_createPool() public view {
        (address token1,, uint256 rewardRate1,,, bool isActive1) = yieldFarming.pools(poolId1);
        (address token2,, uint256 rewardRate2,,, bool isActive2) = yieldFarming.pools(poolId2);

        assertTrue(isActive1);
        assertTrue(isActive2);
        assertEq(token1, address(stakingToken1));
        assertEq(token2, address(stakingToken2));
        assertEq(rewardRate1, REWARD_RATE);
        assertEq(rewardRate2, REWARD_RATE * 2);
    }

    function test_createPool_revertIfTokenIsZero() public {
        vm.expectRevert("Invalid token address");
        yieldFarming.createPool(address(0), REWARD_RATE);
    }

    function test_createPool_revertIfRewardRateIsZero()  public {
        vm.expectRevert("Reward rate must be positive");
        yieldFarming.createPool(address(stakingToken1), 0);
    }

    function test_createPool_revertIfPoolAlreadyExists() public {
        vm.expectRevert("Pool already exists");
        yieldFarming.createPool(address(stakingToken1), REWARD_RATE);
    }

    function test_poolIdIsUnique() public {
        assertTrue(poolId1 != poolId2);
        
        vm.warp(block.timestamp + 1);
        bytes32 poolId3 = yieldFarming.createPool(address(stakingToken1), REWARD_RATE);
        assertTrue(poolId3 != poolId1);
    }

    function test_stake() public {
        uint256 stakeAmount = 1000 * 10**18;

        vm.startPrank(user1);
        yieldFarming.stake(poolId1, stakeAmount);
        vm.stopPrank();

        (uint256 amount,,) = yieldFarming.userInfo(poolId1, user1);
        (,uint256 totalStaked,,,, ) = yieldFarming.pools(poolId1);

        assertEq(amount, stakeAmount);
        assertEq(totalStaked, stakeAmount);
    }

    function test_stake_andGetRewards() public {
        uint256 stakeAmount = 1000 * 10**18;

        vm.startPrank(user1);
        yieldFarming.stake(poolId1, stakeAmount);
        vm.stopPrank();

        // Move forward on timestamp
        vm.warp(block.timestamp + 100);

        // Ensure rewards has been generated
        uint256 pendingRewards = yieldFarming.pendingRewards(poolId1, user1);
        assertGt(pendingRewards, 0);

        // Claim rewards
        vm.startPrank(user1);
        yieldFarming.claimRewards(poolId1);
        vm.stopPrank();

        // Ensure rewards has been transfered
        assertGt(rewardToken.balanceOf(user1), 0);
    }

    function test_stake_multipleUsers() public {
        uint256 stakeAmount1 = 1000 * 10**18;
        uint256 stakeAmount2 = 2000 * 10**18;
        
        // User1 stake en pool1
        vm.startPrank(user1);
        yieldFarming.stake(poolId1, stakeAmount1);
        vm.stopPrank();
        
        // User2 stake en pool1
        vm.startPrank(user2);
        yieldFarming.stake(poolId1, stakeAmount2);
        vm.stopPrank();
        
        // Avanzar tiempo
        vm.warp(block.timestamp + 100);
        
        // Verificar que ambos usuarios tienen recompensas
        uint256 pending1 = yieldFarming.pendingRewards(poolId1, user1);
        uint256 pending2 = yieldFarming.pendingRewards(poolId1, user2);
        
        assertGt(pending1, 0);
        assertGt(pending2, 0);
        
        // User2 debería tener más recompensas por tener más tokens staked
        assertGt(pending2, pending1);
    }

    function test_stake_revertIfPoolIsNotActive() public {
        uint256 stakeAmount = 1000 * 10**18;
        yieldFarming.deactivatePool(poolId1);
        vm.expectRevert("Pool is not active");
        yieldFarming.stake(poolId1, stakeAmount);
    }

    function test_stake_revertIfAmountIsZero() public {
        vm.expectRevert("Cannot stake 0 tokens");
        yieldFarming.stake(poolId1, 0);
    }

    function test_stake_autoClaimIfAmount() public {
        uint256 firstStakeAmount = 100 * 1e18;
        uint256 secondStakeAmount = 50 * 1e18;
        
        stakingToken1.mint(user1, firstStakeAmount + secondStakeAmount);
        rewardToken.mint(address(yieldFarming), 10000 * 1e18);
        
        vm.startPrank(user1);
        stakingToken1.approve(address(yieldFarming), firstStakeAmount);
        yieldFarming.stake(poolId1, firstStakeAmount);
        yieldFarming.withdraw(poolId1, firstStakeAmount);
        stakingToken1.approve(address(yieldFarming), secondStakeAmount);
        
        uint256 rewardBalanceBefore = rewardToken.balanceOf(user1);
        
        yieldFarming.stake(poolId1, secondStakeAmount);
        vm.stopPrank();
        
        uint256 rewardBalanceAfter = rewardToken.balanceOf(user1);
        assertEq(rewardBalanceAfter, rewardBalanceBefore, "Should not auto-claim when pending is 0");
    }

    function test_stake_autoClaimIfPending() public {
        uint256 firstStakeAmount = 100 * 1e18;
        uint256 secondStakeAmount = 50 * 1e18;
        
        stakingToken1.mint(user1, firstStakeAmount + secondStakeAmount);
        
        uint256 rewardFunding = 10000 * 1e18;
        rewardToken.mint(address(yieldFarming), rewardFunding);
        
        vm.startPrank(user1);
        stakingToken1.approve(address(yieldFarming), firstStakeAmount);
        yieldFarming.stake(poolId1, firstStakeAmount);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 100);
        
        vm.startPrank(user1);
        uint256 rewardBalanceBefore = rewardToken.balanceOf(user1);
        uint256 pendingBefore = yieldFarming.pendingRewards(poolId1, user1);
        
        assertGt(pendingBefore, 0, "Should have pending rewards before second stake");
        
        stakingToken1.approve(address(yieldFarming), secondStakeAmount);
        yieldFarming.stake(poolId1, secondStakeAmount);
        vm.stopPrank();
        
        uint256 rewardBalanceAfter = rewardToken.balanceOf(user1);
        
        assertEq(
            rewardBalanceAfter, 
            rewardBalanceBefore + pendingBefore, 
            "Should auto-claim pending rewards on second stake"
        );
    }

    function test_stake_insufficientRewardBalance() public {
        uint256 stake = 500 * 1e18;
        
        stakingToken1.mint(user1, stake * 2);
        
        uint256 poolBalance = rewardToken.balanceOf(address(yieldFarming));
        if (poolBalance > 0) {
            vm.prank(address(yieldFarming));
            rewardToken.transfer(address(0xabc), poolBalance);
        }
        
        rewardToken.mint(address(yieldFarming), 1);
        
        vm.startPrank(user1);
        stakingToken1.approve(address(yieldFarming), stake);
        yieldFarming.stake(poolId1, stake);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 10000);
        
        vm.startPrank(user1);
        stakingToken1.approve(address(yieldFarming), stake);
        yieldFarming.stake(poolId1, stake);
        vm.stopPrank();
    }

    function test_withdraw() public {
        uint256 stakeAmount = 1000 * 10**18;
        uint256 withdrawAmount = 500 * 10**18;
        
        vm.startPrank(user1);
        yieldFarming.stake(poolId1, stakeAmount);
        
        // Move forward on timestamp
        vm.warp(block.timestamp + 100);

        yieldFarming.withdraw(poolId1, withdrawAmount);
        vm.stopPrank();

        // Ensure withdraw has been processed
        (uint256 amount,,) = yieldFarming.userInfo(poolId1, user1);
        (,uint256 totalStaked,,,,) = yieldFarming.pools(poolId1);

        assertEq(amount, stakeAmount - withdrawAmount);
        assertEq(totalStaked, stakeAmount - withdrawAmount);
        assertEq(stakingToken1.balanceOf(user1), 9000 * 10**18 + withdrawAmount);
    }

    function test_withdraw_revertIfInsufficientBalance() public {
        uint256 stakeAmount = 1000 * 10**18;
        uint256 withdrawAmount = 1500 * 10**18;
        
        vm.startPrank(user1);
        yieldFarming.stake(poolId1, stakeAmount);
        
        // Move forward on timestamp
        vm.warp(block.timestamp + 100);

        vm.expectRevert("Insufficient balance");
        yieldFarming.withdraw(poolId1, withdrawAmount);
        vm.stopPrank();
    }

    function test_withdraw_all() public {
        uint256 stakeAmount = 1000 * 10**18;
        uint256 withdrawAmount = 1000 * 10**18;
        
        vm.startPrank(user1);
        yieldFarming.stake(poolId1, stakeAmount);
        
        // Move forward on timestamp
        vm.warp(block.timestamp + 100);

        yieldFarming.withdraw(poolId1, withdrawAmount);
        vm.stopPrank();

        // Ensure withdraw has been processed
        (uint256 amount,,) = yieldFarming.userInfo(poolId1, user1);
        (,uint256 totalStaked,,,,) = yieldFarming.pools(poolId1);

        assertEq(amount, stakeAmount - withdrawAmount);
        assertEq(totalStaked, stakeAmount - withdrawAmount);
        assertEq(stakingToken1.balanceOf(user1), 9000 * 10**18 + withdrawAmount);
    }

    function test_withdraw_autoClaimsRewards() public {
        uint256 stakeAmount = 1000 * 10**18;
        
        vm.startPrank(user1);
        yieldFarming.stake(poolId1, stakeAmount);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 100);
        
        uint256 rewardBalanceBefore = rewardToken.balanceOf(user1);
        
        vm.startPrank(user1);
        yieldFarming.withdraw(poolId1, 500 * 10**18);
        vm.stopPrank();
        
        uint256 rewardBalanceAfter = rewardToken.balanceOf(user1);
        
        assertGt(rewardBalanceAfter, rewardBalanceBefore);
    }

    function test_claimRewards() public {
        uint256 stakeAmount = 1000 * 10**18;

        vm.startPrank(user1);
        yieldFarming.stake(poolId1, stakeAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);

        uint256 rewardBalanceBefore = rewardToken.balanceOf(user1);

        vm.startPrank(user1);
        yieldFarming.claimRewards(poolId1);
        vm.stopPrank();

        uint256 rewardBalanceAfter = rewardToken.balanceOf(user1);

        assertGt(rewardBalanceAfter, rewardBalanceBefore);
    }

    function test_claimRewards_revertIfNoRewards() public {
        vm.startPrank(user1);
        vm.expectRevert("No rewards to claim");
        yieldFarming.claimRewards(poolId1);
        vm.stopPrank();
    }

    function test_updatePoolRewardRate() public {
        uint256 newRewardRate = 2 * 10**16;

        yieldFarming.updatePoolRewardRate(poolId1, newRewardRate);

        (,,uint256 rewardRate,,,) = yieldFarming.pools(poolId1);
        assertEq(rewardRate, newRewardRate);
    }

    function test_updatePoolRewardRate_revertIfPoolNotActive() public {
        uint256 newRewardRate = 2 * 10**16;

        yieldFarming.deactivatePool(poolId1);

        vm.expectRevert("Pool is not active");
        yieldFarming.updatePoolRewardRate(poolId1, newRewardRate);
    }

    function test_pendingRewards() public {
        uint256 stakeAmount = 1000 * 10**18;
    
        vm.startPrank(user1);
        yieldFarming.stake(poolId1, stakeAmount);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 100);
        
        uint256 pending = yieldFarming.pendingRewards(poolId1, user1);
        
        assertGt(pending, 0);
        
        assertGt(pending, 0);
    }

    function test_pendingRewards_ifTotalStakedIsZero() public view {
        uint256 pending = yieldFarming.pendingRewards(poolId1, user1);
        
        assertEq(pending, 0);
    }

    function test_getPoolEncodedData() public view {
        bytes memory encodedData = yieldFarming.getPoolEncodedData(poolId1);

        assertGt(encodedData.length, 0);
        assertTrue(encodedData.length > 0);
    }

    function test_getUserHash() public view {
        bytes32 userHash = yieldFarming.getUserHash(poolId1, user1);

        bytes32 userHash2 = yieldFarming.getUserHash(poolId1, user2);
        assertTrue(userHash != userHash2);

        bytes32 userHashPool2 = yieldFarming.getUserHash(poolId2, user1);
        assertTrue(userHash != userHashPool2);
    }

    function test_getActivePoolsCount() public view {
        bytes32[] memory activePools = yieldFarming.getActivePools();
        assertEq(activePools.length, 2);
        assertEq(activePools[0], poolId1);
        assertEq(activePools[1], poolId2);

        assertEq(yieldFarming.getActivePoolsCount(), 2);
    }

    function test_emergencyWithdraw() public {
        stakingToken1.transfer(address(yieldFarming), 1000 * 10**18);
        
        uint256 balanceBefore = stakingToken1.balanceOf(owner);
        
        yieldFarming.emergencyWithdraw(address(stakingToken1), 1000 * 10**18);
        
        uint256 balanceAfter = stakingToken1.balanceOf(owner);
        assertEq(balanceAfter, balanceBefore + 1000 * 10**18);
    }
}
