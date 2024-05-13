// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ILiquidToken {
    /// @notice Linked Booster
    function booster() external view returns (address);

    /// @notice Mint new tokens by Booster
    /// @dev Only booster can mint
    function mint(address receiver, uint amount) external;
}
