// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IBurnableERC20 {
    /// @notice Destroys a `value` amount of tokens from the caller
    /// @param value Amount of tokens to burn
    function burn(uint value) external;
}
