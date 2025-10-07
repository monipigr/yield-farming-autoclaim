// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title YieldFarming
 * @notice A multi-pool yield farming protocol where users can stake tokens and earn rewards
 * @dev Inherits from Ownable for access control and ReentrancyGuard for security
 */
contract YieldFarming is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Structure to store pool information 
    struct Pool {
        address token;                // ERC20 token accepted for staking in this pool
        uint256 totalStaked;          // Total staked tokens at the pool
        uint256 rewardRate;           // Amount of reward tokens to receive per second
        uint256 lastUpdateTime;       // Timestamp of the last pool state update
        uint256 rewardPerTokenStored; // Amount of accumulated reward per token staked at the pool
        bool isActive;                // Determines if the pool is active or not
    }

    /**
     * @notice Information tracked for each user in each pool
     */
    struct UserInfo {
        uint256 amount;        // Amount of tokens currently staked by the user
        uint256 rewardDebt;    // Reward debt for fair distribution calculation
        uint256 lastClaimTime; // Timestamp of the last reward claim
    }


    /// @notice Token used to distribute rewards to stakers
    /// @dev Set once at deployment and cannot be changed (immutable)
    IERC20 public immutable rewardToken;

    // Mapping of the pools by their unique identifier
    mapping(bytes32 => Pool) public pools;

    // Nested mapping of user information by pool and address
    mapping(bytes32 => mapping(address => UserInfo)) public userInfo; 

    // List of all active pools
    bytes32[] public activePools;

    // Events
    event PoolCreated(bytes32 indexed poolId, address indexed token, uint256 rewardRate);
    event Staked(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Withdrawn(bytes32 indexed poolId, address indexed user, uint256 amount);
    event RewardClaimed(bytes32 indexed poolId, address indexed user, uint256 amount);
    event PoolUpdated(bytes32 indexed poolId, uint256 newRewardRate);
    
    /**
     * @notice Initializes the YieldFarming contract
     * @dev Sets msg.sender as owner via Ownable constructor
     * @param _rewardToken Address of the ERC20 token used for reward distribution
     */
    constructor(address _rewardToken) Ownable(msg.sender) {
        require(_rewardToken != address(0), "Invalid token reward"); 
        rewardToken = IERC20(_rewardToken); // Cast to enable ERC20 function calls
    }

    /**
     * @notice Creates a new yield farming pool
     * @dev Only callable by the contract owner
     * @param token Address of the ERC20 token accepted for staking
     * @param rewardRate Amount of reward tokens distributed per second
     * @return poolId Unique identifier for the created pool
     */
    function createPool(address token, uint256 rewardRate) 
        external 
        onlyOwner 
        returns (bytes32 poolId) 
    {
        // Validation
        require(token != address(0), "Invalid token address");
        require(rewardRate > 0, "Reward rate must be positive");

        // Generate unique pool ID
        poolId = keccak256(
            abi.encodePacked(token, rewardRate, block.timestamp, block.chainid)
        );

        // Ensure pool doesn't already exist
        require(pools[poolId].token == address(0), "Pool already exists");

        // Create and store pool
        pools[poolId] = Pool({
            token: token,
            totalStaked: 0,
            rewardRate: rewardRate,
            lastUpdateTime: block.timestamp,
            rewardPerTokenStored: 0,
            isActive: true
        });

        // Track active pools
        activePools.push(poolId);

        // Emit creation event
        emit PoolCreated(poolId, token, rewardRate);
    }
    
    function stake(bytes32 poolId, uint256 amount) external nonReentrant {
        // 1. Get pool and validate
        Pool storage pool = pools[poolId];
        require(pool.isActive, "Pool is not active");
        require(amount > 0, "Cannot stake 0 tokens");
        
        // 2. Update pool state (rewardPerTokenStored, lastUpdateTime)
        _updatePool(poolId);
        
        // 3. Get user info
        UserInfo storage user = userInfo[poolId][msg.sender];
        
        // 4. Auto-claim pending rewards if user already has tokens staked
        if (user.amount > 0) {
            uint256 pending = _calculatePendingRewards(poolId, msg.sender);
            if (pending > 0) {
                _safeRewardTransfer(msg.sender, pending);
                emit RewardClaimed(poolId, msg.sender, pending);
            }
        }
        
        // 5. Transfer staking tokens from user to contract
        IERC20(pool.token).safeTransferFrom(msg.sender, address(this), amount);
        
        // 6. Update user state
        user.amount += amount;
        user.rewardDebt = user.amount * pool.rewardPerTokenStored / 1e18;
        user.lastClaimTime = block.timestamp;
        
        // 7. Update pool total
        pool.totalStaked += amount;
        
        // 8. Emit event
        emit Staked(poolId, msg.sender, amount);
    }

    /**
     * @notice Withdraw staked tokens from a pool
     * @dev unstake tokens + claim rewards
     * @param poolId Pool identifier
     * @param amount Amount of tokens to withdraw
     */
    function withdraw(bytes32 poolId, uint256 amount) external nonReentrant {
        Pool storage pool = pools[poolId];
        UserInfo storage user = userInfo[poolId][msg.sender];
        // Comprobar que solo retiramos nuestros tokens
        require(amount <= user.amount, "Insufficient balance"); // Sería mejor con = ? Es decir que la cantidad que quiere retirar el sender es la misma que la que tiene

        // Actualizamos la pool
        _updatePool(poolId);

        // Calculamos los rewards que nos tocan. Si hay pending rewards los transferimos + evento
        uint256 pending = _calculatePendingRewards(poolId, msg.sender);
        if(pending > 0) {
            _safeRewardTransfer(msg.sender, pending);
            // rewardToken.transfer(msg.sender, pending);
            emit RewardClaimed(poolId, msg.sender, pending);
        }

        // Actualizamos los objetos de Pool y User
        user.amount -= amount;
        user.rewardDebt = user.amount * pool.rewardPerTokenStored / 1e18;
        pool.totalStaked -= amount;
        // Transferimos + evento
        IERC20(pool.token).safeTransfer(msg.sender, amount);
        emit Withdrawn(poolId, msg.sender, amount);
    }


    // mapping(bytes32 => Pool) public pools;   struct Pool { address token; uint256 totalStaked; uint256 rewardRate; uint256 lastUpdateTime; uint256 rewardPerTokenStored; bool isActive; }
    // mapping(bytes32 => mapping(address => UserInfo)) public userInfo; struct UserInfo { uint256 amount; uint256 rewardDebt;uint256 lastClaimTime; }
    /**
     * @dev Claim pending rewards
     * @param poolId Pool identifier
     */
    function claimRewards(bytes32 poolId) external nonReentrant {
        UserInfo storage user = userInfo[poolId][msg.sender];
        Pool storage pool = pools[poolId];
        // Actualizar pool
        _updatePool(poolId);
        // Calcular pending rewards
        uint256 pending = _calculatePendingRewards(poolId, msg.sender);
        require(pending > 0, "No rewards to claim");
        user.rewardDebt = user.amount * pool.rewardPerTokenStored / 1e18; 
        user.lastClaimTime = block.timestamp;
            
        _safeRewardTransfer(msg.sender, pending);

        emit RewardClaimed(poolId, msg.sender, pending);
    }
    /**
     * @dev Update the reward rate of a pool
     * @param poolId Pool identifier
     * @param newRewardRate New reward rate
     */
    function updatePoolRewardRate(bytes32 poolId, uint256 newRewardRate) external onlyOwner {
        Pool storage pool = pools[poolId];
        require(pool.isActive, "Pool is not active");
        
        _updatePool(poolId);
        pool.rewardRate = newRewardRate;
        
        emit PoolUpdated(poolId, newRewardRate);
    }

    /**
     * @dev Calculate the pending rewards of a user
     * @param poolId Pool identifier
     * @param user User address
     * @return Amount of pending rewards
     */
    function pendingRewards(bytes32 poolId, address user) external view returns (uint256) {
        Pool storage pool = pools[poolId];
        UserInfo storage userInfoData = userInfo[poolId][user];
        
        uint256 rewardPerTokenStored = pool.rewardPerTokenStored;
        
        if (pool.totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - pool.lastUpdateTime;
            uint256 rewards = timeElapsed * pool.rewardRate;
            rewardPerTokenStored += rewards * 1e18 / pool.totalStaked;
        }
        
        return userInfoData.amount * rewardPerTokenStored / 1e18 - userInfoData.rewardDebt;
    }


    /**
     * @dev Get encoded pool information for external use
     * @param poolId Pool identifier
     * @return encodedData Encoded pool data
     * 
     * DEMONSTRATION: This method shows how to use abi.encodePacked to
     * create compact data that can be used in other contracts
     */    
    function getPoolEncodedData(bytes32 poolId) external view returns (bytes memory encodedData) { 
        Pool storage pool = pools[poolId];
        
        encodedData = abi.encodePacked(
            pool.token,
            pool.totalStaked,
            pool.rewardRate,
            pool.lastUpdateTime,
            pool.rewardPerTokenStored,
            pool.isActive
        );
    }

    /**
     * @dev Create a unique hash for a user in a specific pool
     * @param poolId Pool identifier
     * @param user User address
     * @return userHash Unique user hash
     * 
     * DEMONSTRATION: Use of abi.encodePacked to create unique identifiers
     * by combining multiple parameters
     */
    function getUserHash(bytes32 poolId, address user) external pure returns (bytes32 userHash) {
        userHash = keccak256(
            abi.encodePacked(
                poolId,
                user,
                "YIELD_FARMING_USER"
            )
        );
    }

    /**
     * @dev Get the total number of active pools
     * @return Number of active pools
     */
    function getActivePoolsCount() external view returns (uint256) {
        return activePools.length;
    }

    /**
     * @dev Get all active pools
     * @return Array with the identifiers of the active pools
     */
    function getActivePools() external view returns (bytes32[] memory) {
        return activePools;
    }

    /**
     * Allows owner to deactive a pool
     * @param poolId Unique identifier of the pool
     */
    function deactivatePool(bytes32 poolId) external onlyOwner {
        pools[poolId].isActive = false;
    }

    /**
     * @dev Calculate the pending rewards of a user
     * @param poolId Pool identifier
     * @param user User address
     * @return Amount of pending rewards
     */
    function _calculatePendingRewards(bytes32 poolId, address user) internal view returns (uint256) {
        Pool storage pool = pools[poolId];
        UserInfo storage userInfoData = userInfo[poolId][user];
        
        uint256 rewardPerTokenStored = pool.rewardPerTokenStored;
        
        if (pool.totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - pool.lastUpdateTime;
            uint256 rewards = timeElapsed * pool.rewardRate;
            rewardPerTokenStored += rewards * 1e18 / pool.totalStaked;
        }
        
        return userInfoData.amount * rewardPerTokenStored / 1e18 - userInfoData.rewardDebt;
    }

    /**
     * Updates the pool state
     * @param poolId Unique identifier of the pool to be updated
     */
    function _updatePool(bytes32 poolId) internal {
        Pool storage pool = pools[poolId];

        if(pool.totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - pool.lastUpdateTime;
            uint256 rewards = timeElapsed * pool.rewardRate;
            pool.rewardPerTokenStored += rewards * 1e18 / pool.totalStaked; 
        }
        pool.lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Safely transfer rewards
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function _safeRewardTransfer(address to, uint256 amount) internal {
        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        if (amount > rewardBalance) {
            amount = rewardBalance;
        }
        if (amount > 0) {
            rewardToken.safeTransfer(to, amount);
        }
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

}
