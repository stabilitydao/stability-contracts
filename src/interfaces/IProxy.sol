// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev Proxy of core contract implementation
interface IProxy {
    /// @dev Initialize proxy logic. Need to call after deploy new proxy.
    /// @param logic Address of core contract implementation
    function initProxy(address logic) external;

    /// @notice Upgrade proxy implementation (contract logic).
    /// @dev Upgrade execution allowed only for Platform contract.
    /// An upgrade of any core contract proxy is always part of a platform time locked upgrade,
    /// with a change in the platform version.
    /// @param newImplementation New implementation address
    function upgrade(address newImplementation) external;

    /// @notice Return current logic implementation
    /// @return Address of implementation contract
    function implementation() external view returns (address);
}
