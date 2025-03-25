// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IRevenueRouter {
    error WaitForNewPeriod();

    /// @notice Update the epoch (period) -- callable once a week at >= Thursday 0 UTC
    /// @return newPeriod The new period
    function updatePeriod() external returns (uint newPeriod);

    /// @notice The period used for rewarding
    /// @return The block.timestamp divided by 1 week in seconds
    function getPeriod() external view returns (uint);

    /// @notice Current active period
    function activePeriod() external view returns (uint);

    /// @notice Accumulated STBL amount for next distribution
    function pendingRevenue() external view returns (uint);
}
