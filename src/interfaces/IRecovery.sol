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

    /// @notice Return list of registered tokens with amounts exceeding thresholds
    function getListTokensToSwap() external view returns (address[] memory tokens);

    /// @notice Return full list of registered tokens
    function getListRegisteredTokens() external view returns (address[] memory tokens);

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

    /// @notice Swap registered tokens to meta vault tokens. The meta vault token is selected from the given recovery pool.
    /// @param tokens Addresses of registered tokens to be swapped. They should be asked through {getListTokensToSwap}
    /// Number of tokens should be limited to avoid gas limit excess, so this function probably should be called several times
    /// to swap all available tokens.
    /// @param indexRecoveryPool1 1-based index of the recovery pool.
    /// The given pool is used to select target meta vault token. If 0 the pool will be selected automatically.
    function swapAssets(address[] memory tokens, uint indexRecoveryPool1) external;

    /// @notice Swap meta vault tokens from the balance of this contract to recovery tokens in the registered pools
    /// @param indexFirstRecoveryPool1 1-based index of the recovery pool from which swapping should be started.
    /// If zero then the initial pool will be selected automatically.
    /// It's allowed to pass index of the pool with "wrong" meta vault token (not equal to {metaVaultToken_}). In this case
    /// the pool will be just skipped, swapping will be done in other pools.
    /// @param metaVaultToken_ Address of the meta vault token to be swapped. All pools with the given token will be used,
    /// all other pools will be ignored.
    /// @param maxCountPools Maximum number of pools to be used for swapping. 0 - no limits
    function fillRecoveryPools(address metaVaultToken_, uint indexFirstRecoveryPool1, uint maxCountPools) external;
}
