// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ILiquidBoxManager {
    function deposit(
        address box,
        uint deposit0,
        uint deposit1,
        uint amount0Min,
        uint amount1Min
    ) external payable returns (uint shares);

    function withdraw(
        address box,
        uint shares,
        uint amount0Min,
        uint amount1Min
    ) external returns (uint amount0, uint amount1);
}
