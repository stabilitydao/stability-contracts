// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IRecoveryBase {
    /// @dev Init
    function initialize(address platform_) external;

    /// @notice Revenue Router calls this function to notify that some tokens were transferred to this contract
    /// @param tokens Addresses of the tokens that were transferred
    function registerAssets(address[] memory tokens) external;
}
