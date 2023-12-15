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
    function getPriceAtTick(address pool, address tokenIn, int24 tick) external view returns (uint);

    /// @notice Priced proportions of pool assets in specified range
    /// @param pool Address of a pool supported by the adapter
    /// @param ticks Tick boundaries. Lower and upper ticks for UniswapV3-like AMM position.
    /// @return Proportions with 5 decimals precision. Max is 100_000, min is 0.
    function getProportions(address pool, int24[] memory ticks) external view returns (uint[] memory);

    /// @notice Computes the maximum amount of liquidity received for given amounts of pool assets and the current
    /// pool prices and the prices at the tick boundaries
    /// @param pool Address of a pool supported by the adapter
    /// @param amounts Ampunts of pool assets
    /// @param ticks Tick boundaries. Lower and upper ticks for UniswapV3-like AMM position.
    /// @return liquidity Liquidity out value
    /// @return amountsConsumed Amounts of consumed assets of provided liquidity
    function getLiquidityForAmounts(
        address pool,
        uint[] memory amounts,
        int24[] memory ticks
    ) external view returns (uint liquidity, uint[] memory amountsConsumed);

    /// @notice Computes pool assets amounts for a given amount of liquidity, the current
    /// pool prices and the prices at the tick boundaries
    /// @param pool Address of a pool supported by the adapter
    /// @param ticks Tick boundaries. Lower and upper ticks for UniswapV3-like AMM position.
    /// @param liquidity Liquidity value
    /// @return amounts Amounts out of provided liquidity
    function getAmountsForLiquidity(
        address pool,
        int24[] memory ticks,
        uint128 liquidity
    ) external view returns (uint[] memory amounts);
}
