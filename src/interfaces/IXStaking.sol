// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IXStaking {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event Deposit(address indexed from, uint amount);

    event Withdraw(address indexed from, uint amount);

    event NotifyReward(address indexed from, uint amount);
    event ClaimRewards(address indexed from, uint amount);

    event NewDuration(uint oldDuration, uint newDuration);

    event RewardTokenAllowed(address indexed token, bool allowed);
    event NotifyRewardForToken(address indexed token, address indexed from, uint amount);
    event ClaimRewardsForToken(address indexed token, address indexed from, uint amount);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error DaoNotInitialized();
    error TokenNotAllowed(address token);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Deposits all xToken in the caller's wallet
    function depositAll() external;

    /// @notice Deposit a specified amount of xToken
    function deposit(uint amount) external;

    /// @notice Withdraw all xToken and claim rewards
    function withdrawAll() external;

    /// @notice Withdraw a specified amount of xToken
    function withdraw(uint amount) external;

    /// @notice Claims pending rebase rewards
    function getReward() external;

    /// @notice Used to notify pending xToken rebases and platform revenue share
    /// @param amount The amount of main token to be notified
    function notifyRewardAmount(uint amount) external;

    /// @notice Change duration period
    function setNewDuration(uint) external;

    /// @notice Updates DAO-token balances for the given users.
    /// @custom:restricted Only operator
    /// @dev If a user has less than the minimum staking power of xToken, his DAO-token balance will be zero.
    /// Otherwise, the user receives 1 DAO-token for each 1 xToken staked.
    function syncDAOBalances(address[] calldata users) external;

    /// @notice Allow or disallow reward token
    /// @param token Address of reward token
    /// @param allowed Allowed state
    /// @custom:restricted Only operator
    function allowRewardToken(address token, bool allowed) external;

    /// @notice Used to notify pending xToken rebases and platform revenue share
    /// @custom:restricted Only RevenueRouter or xToken
    /// @param token Address of reward token
    /// @param amount The amount of main token to be notified
    function notifyRewardAmountToken(address token, uint amount) external;

    /// @notice Claims pending rewards
    /// @param token Address of reward token
    function getRewardToken(address token) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // common data

    /// @notice The address of the xToken token (staking/voting token)
    /// @return xToken address
    function xToken() external view returns (address);

    /// @notice Returns the total voting power (equal to total supply in the XStaking)
    function totalSupply() external view returns (uint);

    /// @notice The duration of notified rewards distribution
    function duration() external view returns (uint);

    /// @notice Staked amount
    /// @param user the address to check
    /// @return The staked balance
    function balanceOf(address user) external view returns (uint);

    // legacy data

    /// @notice Returns the last time the reward was modified or periodFinish if the reward has ended
    function lastTimeRewardApplicable() external view returns (uint);

    /// @notice Last time the rewards system was updated
    function lastUpdateTime() external view returns (uint);

    /// @notice The amount of rewards per xToken
    function rewardPerTokenStored() external view returns (uint);

    /// @notice When the 1800 seconds after notifying are up
    function periodFinish() external view returns (uint);

    /// @notice Calculates the rewards distributed per second
    function rewardRate() external view returns (uint);

    /// @dev Current calculated reward per token
    /// @return The return value is scaled (multiplied) by PRECISION = 10 ** 18
    function rewardPerToken() external view returns (uint);

    /// @notice The amount of rewards claimable for the user
    /// @param user the address of the user to check
    /// @return The stored rewards
    function storedRewardsPerUser(address user) external view returns (uint);

    /// @notice Rewards per amount of xToken's staked
    function userRewardPerTokenStored(address user) external view returns (uint);

    /// @notice User's earned reward
    function earned(address account) external view returns (uint);

    // reward tokens data

    /// @notice Is token allowed for rewards
    function isTokenAllowed(address token) external view returns (bool);

    /// @notice User's earned reward of token
    /// @param token Address of reward token
    /// @param account Address of user
    function earnedToken(address token, address account) external view returns (uint);
}
