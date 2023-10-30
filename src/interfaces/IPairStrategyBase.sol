// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "../interfaces/IDexAdapter.sol";

/// @dev This interface mostly used for initializing PairStrategyBase
interface IPairStrategyBase {
    event FeesClaimed(uint fee0, uint fee1);

    struct PairStrategyBaseInitParams {
        string id;
        address platform;
        address vault;
        address pool;
        address underlying;
    }

    /// @dev DeX adapter string ID for interacting with pool
    function DEX_ADAPTER_ID() external view returns(string memory);

    /// @dev DeX adapter address for interacting with pool
    function dexAdapter() external view returns (IDexAdapter);

    /// @dev AMM
    function pool() external view returns (address);
}
