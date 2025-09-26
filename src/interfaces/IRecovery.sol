// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IRecovery {
    /// @dev Init
    function initialize(address platform_) external;

    /// @notice Returns the list of registered recovery pools
    function recoveryPools() external view returns (address[] memory);

    /// @notice Returns the threshold amount for the given token
    function threshold(address token) external view returns (uint);

    /// @notice Returns true if the operator is whitelisted
    /// Multisig is always whitelisted.
    function whitelisted(address operator_) external view returns (bool);

    /// @notice Returns true if the token is registered by {registerAssets}
    function isTokenRegistered(address token) external view returns (bool);

    /// @notice Add recovery pools to the list of registered pools
    function addRecoveryPools(address[] memory recoveryPools_) external;

    /// @notice Remove recovery pool from the list of registered pools
    function removeRecoveryPool(address pool_) external;

    /// @notice Set threshold amounts for the given tokens
    function setThresholds(address[] memory tokens, uint[] memory thresholds) external;

    /// @notice Add or remove operator from the whitelist
    function changeWhitelist(address operator_, bool add_) external;

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
