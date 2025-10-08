# 🌾 Yield Farming with Auto-Claim

A decentralized yield farming protocol featuring automatic reward claiming on stakes and withdrawals, and also manual claiming. Users can stake ERC-20 tokens across multiple pools and earn rewards over time. Built with Solidity and Foundry with a complete testing suite for robustness.

## ✨ Features

- 🏊 **Multi-Pool Support**: create and manage multiple yield farming pools with different staking tokens and reward rates
- 💰 **Auto-Claim on Stake**: automatically claim pending rewards when staking additional tokens
- 💸 **Auto-Claim on Withdraw**: automatically claim pending rewards when withdrawing staked tokens
- 🔄 **Manual Claim**: users can claim rewards at any time without staking or withdrawing
- 📈 **Dynamic Reward Rates**: owner can adjust reward rates per pool after creation
- 🛡️ **Safe Reward Transfer**: prevents reverts when pool has insufficient reward balance—transfers available balance instead
- 🚨 **Emergency Withdrawal**: owner can rescue stuck tokens or ETH if needed
- ⏱️ **Time-Based Rewards**: rewards accumulate based on time staked and reward rate per second
- 🔍 **Query Functions**: external view functions to check pending rewards, active pools, and user balances
- 🎯 **Unique Pool IDs**: each pool is identified by a unique bytes32 hash based on token, reward rate, timestamp, and chain ID

## 🔐 Security Measures and Patterns

- 🪙 **SafeERC20**: all token transfers use `SafeERC20` to handle non-standard ERC20 implementations safely
- 🔑 **Access Control**: `onlyOwner` modifier restricts privileged functions (`createPool`, `updatePoolRewardRate`, `emergencyWithdraw`, etc.)
- 🛡️ **Reentrancy Protection**: critical functions (`stake`, `withdraw`, `claimTokens`) are protected with OpenZeppelin’s `ReentrancyGuard`
- 🧩 **CEI Pattern**: all external functions follow the Checks-Effects-Interactions pattern to minimize vulnerabilities
- ✅ **Input Validation**: comprehensive checks for zero addresses, zero amounts, active pools, and sufficient balances
  -🛡️ **Safe Reward Distribution**: `_safeRewardTransfer()` prevents reverts by transferring only available balance when reward pool is insufficient
- 📢 **Event Logging**: all state mutations emit events (`PoolCreated`, `Staked`, `Withdrawn`, `RewardClaimed`, `PoolUpdated`) for transparency and off-chain monitoring
- 🧪 **Testing**: complete testin suite with 100% coverage

## 🧪 Tests

Complete testing suite using **Foundry**, achieving a 100% code coverage across both contracts.
The suite includes happy paths, negative paths and edge cases to ensure robustness.

Ran 2 test suites in 243.63ms (13.30ms CPU time): 31 tests passed, 0 failed, 0 skipped (31 total tests)

╭----------------------+-------------------+-------------------+-----------------+-----------------╮
| File | % Lines | % Statements | % Branches | % Funcs |
+==================================================================================================+
| src/MockToken.sol | 100.00% (6/6) | 100.00% (3/3) | 100.00% (0/0) | 100.00% (3/3) |
|----------------------+-------------------+-------------------+-----------------+-----------------|
| src/YieldFarming.sol | 100.00% (102/102) | 100.00% (102/102) | 100.00% (26/26) | 100.00% (16/16) |
|----------------------+-------------------+-------------------+-----------------+-----------------|
| Total | 100.00% (108/108) | 100.00% (105/105) | 100.00% (26/26) | 100.00% (19/19) |
╰----------------------+-------------------+-------------------+-----------------+-----------------╯

Run tests with:

```bash
forge test --vvvv --match-test test_stake_andGetRewards
```

## 🧠 Technologies Used

- ⚙️ **Solidity** (`^0.8.19`) – smart contract programming language
- 🧪 **Foundry** – framework for development, testing, fuzzing, invariants and deployment
- 📚 **OpenZeppelin Contracts** – `ERC20`, `Ownable`, `ReentrancyGuard`, `SafeERC20`
- 🛠️ **MockToken** – custom ERC20 token implementation with mint function for testing

## 📜 License

This project is licensed under the MIT License.
