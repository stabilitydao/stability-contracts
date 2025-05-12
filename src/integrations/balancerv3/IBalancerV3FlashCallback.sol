// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IBalancerV3FlashCallback {
  function receiveFlashLoanV3(address token, uint amount, bytes memory userData) external;
}