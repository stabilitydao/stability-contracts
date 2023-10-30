// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IVaultProxy {

  function initProxy(string memory type_) external;

  function upgrade() external;

  function implementation() external view returns (address);

  function VAULT_TYPE_HASH() external view returns (bytes32);

}
