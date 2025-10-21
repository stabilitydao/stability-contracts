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

    event InitializeStabilityDAO(address stblDao);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Deposits all xSTBL in the caller's wallet
    function depositAll() external;

    /// @notice Deposit a specified amount of xSTBL
    function deposit(uint amount) external;

    /// @notice Withdraw all xSTBL and claim rewards
    function withdrawAll() external;

    /// @notice Withdraw a specified amount of xSTBL
    function withdraw(uint amount) external;

    /// @notice Claims pending rebase rewards
    function getReward() external;

    /// @notice Used to notify pending xSTBL rebases and platform revenue share
    /// @param amount The amount of STBL to be notified
    function notifyRewardAmount(uint amount) external;

    /// @notice Change duration period
    function setNewDuration(uint) external;

    /// @notice Update balance of STBLDAO token for all given users
    /// If a user has less then min power xSTBL staked, their STBLDAO balance will be 0
    /// otherwise user should receive 1 STBLDAO for each 1 xSTBL
    function syncStabilityDAOBalances(address[] calldata users) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the last time the reward was modified or periodFinish if the reward has ended
    function lastTimeRewardApplicable() external view returns (uint);

    /// @notice The address of the xSTBL token (staking/voting token)
    /// @return xSTBL address
    function xSTBL() external view returns (address);

    /// @notice Returns the total voting power (equal to total supply in the XStaking)
    function totalSupply() external view returns (uint);

    /// @notice Last time the rewards system was updated
    function lastUpdateTime() external view returns (uint);

    /// @notice The amount of rewards per xSTBL
    function rewardPerTokenStored() external view returns (uint);

    /// @notice When the 1800 seconds after notifying are up
    function periodFinish() external view returns (uint);

    /// @notice Calculates the rewards distributed per second
    function rewardRate() external view returns (uint);

    /// @notice The duration of notified rewards distribution
    function duration() external view returns (uint);

    /// @dev Current calculated reward per token
    /// @return The return value is scaled (multiplied) by PRECISION = 10 ** 18
    function rewardPerToken() external view returns (uint);

    /// @notice The amount of rewards claimable for the user
    /// @param user the address of the user to check
    /// @return The stored rewards
    function storedRewardsPerUser(address user) external view returns (uint);

    /// @notice Rewards per amount of xSTBL's staked
    function userRewardPerTokenStored(address user) external view returns (uint);

    /// @notice User's earned reward
    function earned(address account) external view returns (uint);

    /// @notice Voting power
    /// @param user the address to check
    /// @return The staked balance
    function balanceOf(address user) external view returns (uint);
}
