// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IStrategyProxy {

  function initStrategyProxy(string memory id) external;

  function upgrade() external;

  function implementation() external view returns (address);

  function STRATEGY_IMPLEMENTATION_LOGIC_ID_HASH() external view returns (bytes32);

}
