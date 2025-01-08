// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

interface IVoterV3 {
    /// @notice claim LP gauge rewards
    function claimRewards(address[] memory _gauges) external;

    /// @notice notify reward amount for gauge
    /// @dev    the function is called by the minter each epoch. Anyway anyone can top up some extra rewards.
    /// @param  amount  amount to distribute
    function notifyRewardAmount(uint amount) external;

    /// @notice distribute reward onyl for given gauges
    /// @dev    this function is used in case some distribution fails
    function distribute(address[] memory _gauges) external;

    function minter() external view returns (address);
}
