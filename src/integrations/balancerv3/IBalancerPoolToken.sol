// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IBalancerPoolToken {
    function getVault() external view returns (address);
}
