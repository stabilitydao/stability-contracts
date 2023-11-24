// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./IAmmAdapter.sol";

/// @dev Adapter for interacting with Concentrated Automated Market Make
/// based on liquidity pool of 2 tokens.
/// @author Alien Deployer (https://github.com/a17)
interface ICAmmAdapter is IAmmAdapter {

    /// @notice Price in pool at specified tick
    /// @param pool Address of a pool supported by the adapter
    /// @param tokenIn Token for sell
    /// @return Output amount of swap 1.0 tokenIn in pool without price impact
    function getPriceAtTick(
        address pool,
        address tokenIn,
        int24 tick
    ) external view returns (uint);
}
