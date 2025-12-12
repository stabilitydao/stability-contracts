// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRecoveryBase} from "./IRecoveryBase.sol";

interface IRecoveryRelayer is IRecoveryBase {
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

    /// @notice Set threshold amounts for the given tokens
    function setThresholds(address[] memory tokens, uint[] memory thresholds) external;

    /// @notice Add or remove operator from the whitelist
    function changeWhitelist(address operator_, bool add_) external;

    // todo function swapAssets(address[] memory tokens) external;
}
