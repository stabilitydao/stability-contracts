// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IICHIVault {
    function ichiVaultFactory() external view returns (address);

    function pool() external view returns (address);
    function token0() external view returns (address);
    function allowToken0() external view returns (bool);
    function token1() external view returns (address);
    function allowToken1() external view returns (bool);
    function fee() external view returns (uint24);
    function tickSpacing() external view returns (int24);
    function affiliate() external view returns (address);

    function baseLower() external view returns (int24);
    function baseUpper() external view returns (int24);
    function limitLower() external view returns (int24);
    function limitUpper() external view returns (int24);

    function deposit0Max() external view returns (uint);
    function deposit1Max() external view returns (uint);
    function maxTotalSupply() external view returns (uint);
    function totalSupply() external view returns (uint);
    function hysteresis() external view returns (uint);
    function currentTick() external view returns (int);

    function getTotalAmounts() external view returns (uint, uint);

    function deposit(uint, uint, address) external returns (uint);

    function withdraw(uint, address) external returns (uint, uint);

    function collectFees() external returns (uint fees0, uint fees1);
}
