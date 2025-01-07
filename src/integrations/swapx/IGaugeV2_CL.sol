// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

/// @dev https://sonicscan.org/address/0x413610103721df45c7e8333d5e34bb39975762f3#code
interface IGaugeV2_CL {
    /// @notice deposit all TOKEN of msg.sender
    function depositAll() external;

    /// @notice deposit amount TOKEN
    function deposit(uint amount) external;

    /// @notice withdraw all token
    function withdrawAll() external;

    /// @notice withdraw a certain amount of TOKEN
    function withdraw(uint amount) external;

    /// @notice User harvest function called from distribution (voter allows harvest on multiple gauges)
    function getReward(address _user) external;

    /// @notice User harvest function
    function getReward() external;

    /// @dev Receive rewards from distribution
    function notifyRewardAmount(address token, uint reward) external;

    /// @notice get total reward for the duration
    function rewardForDuration() external view returns (uint);

    /// @notice see earned rewards for user
    function earned(address account) external view returns (uint);

    /// @notice  reward for a single token
    function rewardPerToken() external view returns (uint);

    /// @notice last time reward
    function lastTimeRewardApplicable() external view returns (uint);

    /// @notice balance of a user
    function balanceOf(address account) external view returns (uint);

    /// @notice total supply held
    function totalSupply() external view returns (uint);
}
