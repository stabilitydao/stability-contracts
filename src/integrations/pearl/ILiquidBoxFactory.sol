// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ILiquidBoxFactory {
    function getBoxByPool(address pool) external view returns (address);
}
