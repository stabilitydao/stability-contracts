// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;


interface IManagedVault {
    function changeParams(address[] memory vaultInitAddresses, uint[] memory vaultInitNums) external;
}
