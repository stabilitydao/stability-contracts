// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ILiquidToken {
    /// @notice Mint new tokens by Booster
    function mint(uint amount, address receiver) external;
}