// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Silo share token hook receiver for the gauge
interface ISiloGaugeHookReceiver {
  /// @notice Get the gauge for the share token
  /// @param _shareToken Share token
  function configuredGauges(address _shareToken) external view returns (address);
}
