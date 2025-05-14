// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IBalancerV3FlashCallback {

  /// @notice This callback is called inside IVaultMainV3.unlock (balancer v3)
  /// @dev Support of FLASH_LOAN_KIND_BALANCER_V3
  /// @param token Token of flash loan
  /// @param amount Required amount of the flash loan
  function receiveFlashLoanV3(address token, uint amount, bytes memory userData) external;
}