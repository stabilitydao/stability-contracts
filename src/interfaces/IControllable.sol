// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @dev Base core interface implemented by most platform contracts.
///      Inherited contracts store an immutable Platform proxy address in the storage,
///      which provides authorization capabilities and infrastructure contract addresses.
/// @author Alien Deployer (https://github.com/a17)
interface IControllable {

  event ContractInitialized(address platform, uint ts, uint block);

  /// @notice Stability Platform main contract address
  function platform() external view returns (address);

  /// @notice Version of contract implementation
  /// @dev SemVer scheme MAJOR.MINOR.PATCH
  function version() external view returns (string memory);

  /// @notice Block number when contract was initialized
  function createdBlock() external view returns (uint);

}
