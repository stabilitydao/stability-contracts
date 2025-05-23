// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IFeeTreasury {
    /// @notice List of claimers with their shares
    function claimers() external view returns (address[] memory claimerAddresses, uint[] memory shares);

    /// @notice Distribute and claim your share of fees
    /// @return outAssets Assets that transferred to you
    /// @return amounts Amounts that transferred to you
    function harvest() external returns (address[] memory outAssets, uint[] memory amounts);
}
