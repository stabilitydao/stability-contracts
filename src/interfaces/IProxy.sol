// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IProxy {

  function initProxy(address logic) external;

  function upgrade(address newImplementation) external;

  function implementation() external view returns (address);

}
