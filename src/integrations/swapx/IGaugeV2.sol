// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IGaugeV2 {
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

    /// @notice see earned rewards for user
    function earned(address account) external view returns (uint);

    /// @notice LP address
    function TOKEN() external view returns (address);

    /// @notice Reward token
    function rewardToken() external view returns (address);
}
