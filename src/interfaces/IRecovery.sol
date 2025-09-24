// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IRecovery {

    /// @dev Init
    function initialize(address platform_) external;

    /// @notice Revenue Router calls this function to notify that some tokens were transferred to this contract
    /// @param tokens Addresses of the tokens that were transferred
    function registerAssets(address[] memory tokens) external;

    /// @notice Use available tokens to buy and burn recovery tokens from the registered pools.
    /// @param indexFirstRecoveryPool1 1-based index of the recovery pool from which swapping should be started.
    /// If zero then the initial pool will be selected automatically.
    /// Max swap amount for each pool is limited by price - result prices cannot exceed 1.
    /// If price reaches 1 the remain amount should be used for swapping in other pools.
    function swapAssetsToRecoveryTokens(uint indexFirstRecoveryPool1) external;
}
