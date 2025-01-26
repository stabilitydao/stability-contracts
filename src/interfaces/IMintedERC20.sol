// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IMintedERC20 {
    /// @notice Mint token by owner
    /// @param to Address of receiver
    /// @param amount Amount of tokens to mint
    function mint(address to, uint amount) external;
}
