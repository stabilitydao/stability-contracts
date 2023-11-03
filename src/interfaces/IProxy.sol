// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @dev Platform proxy interface for core contracts
interface IProxy {

  /// @dev Initialize proxy implementation. Need to call after deploy new proxy.
  function initProxy(address logic) external;

  /// @notice Upgrade proxy implementation (contract logic).
  /// @dev Upgrade execution allowed only for Platform contract.
  /// An upgrade of any core contract proxy is always part of a platform time locked upgrade,
  /// with a change in the platform version.
  /// @param newImplementation New implementation address
  function upgrade(address newImplementation) external;

  /// @notice Return current logic implementation
  function implementation() external view returns (address);

}
