// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "../interfaces/IDexAdapter.sol";

/// @dev Liquidity providing strategy

interface ILPStrategy {
    event FeesClaimed(uint[] fees);

    struct LPStrategyBaseInitParams {
        string id;
        address platform;
        address vault;
        address pool;
        address underlying;
    }

    /// @dev DeX adapter string ID for interacting with pool
    function dexAdapterId() external view returns(string memory);

    /// @dev DeX adapter address for interacting with pool
    function dexAdapter() external view returns (IDexAdapter);

    /// @dev AMM
    function pool() external view returns (address);
}
