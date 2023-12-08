// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev Interface of proxy contract for a strategy implementation
interface IStrategyProxy {
    /// @notice Initialize strategy proxy by Factory
    /// @param id Strategy logic ID string
    function initStrategyProxy(string memory id) external;

    /// @notice Upgrade strategy implementation if available and allowed
    /// Anyone can execute strategy upgrade
    function upgrade() external;

    /// @notice Current strategy implementation
    /// @return Address of strategy implementation contract
    function implementation() external view returns (address);

    /// @notice Strategy logic hash
    /// @return keccan256 hash of strategy logic ID string
    function strategyImplementationLogicIdHash() external view returns (bytes32);
}
