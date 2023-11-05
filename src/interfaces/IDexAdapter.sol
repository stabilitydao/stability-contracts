// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @dev Get price, swap, liquidity calculations. Used by strategies and swapper
/// @author Alien Deployer (https://github.com/a17)
interface IDexAdapter {
    event SwapInPool (
        address pool,
        address tokenIn,
        address tokenOut,
        address recipient,
        uint priceImpactTolerance,
        uint amountIn,
        uint amountOut
    );

    struct SwapCallbackData {
        address tokenIn;
        uint amount;
    }

    /// @notice String ID of the adapter
    function DEX_ADAPTER_ID() external view returns(string memory);

    /// @notice Tokens of a pool supported by the adapter
    function poolTokens(address pool) external view returns (address[] memory);

    /// @notice Computes the maximum amount of liquidity received for given amounts of pool assets and the current
    /// pool price.
    /// This function signature can be used only for non-concentrated AMMs.
    /// @param pool Address of a pool supported by the adapter
    /// @param amounts Ampunts of pool assets
    /// @return liquidity Liquidity out value
    /// @return amountsConsumed Amounts of consumed assets when providing liquidity
    function getLiquidityForAmounts(address pool, uint[] memory amounts) external view returns (uint liquidity, uint[] memory amountsConsumed);

    /// @notice Computes the maximum amount of liquidity received for given amounts of pool assets and the current
    /// pool prices and the prices at the tick boundaries
    /// This function signature can be used only for CAMMs.
    /// @param pool Address of a pool supported by the adapter
    /// @param amounts Ampunts of pool assets
    /// @param ticks Tick boundaries. Lower and upper ticks for UniswapV3-like AMM position.
    /// @return liquidity Liquidity out value
    /// @return amountsConsumed Amounts of consumed assets of provided liquidity
    function getLiquidityForAmounts(address pool, uint[] memory amounts, int24[] memory ticks) external view returns (uint liquidity, uint[] memory amountsConsumed);

    /// @notice Computes pool assets amounts for a given amount of liquidity, the current
    /// pool prices and the prices at the tick boundaries
    /// @param pool Address of a pool supported by the adapter
    /// @param ticks Tick boundaries. Lower and upper ticks for UniswapV3-like AMM position.
    /// @param liquidity Liquidity value
    /// @return amounts Amounts out of provided liquidity
    function getAmountsForLiquidity(address pool, int24[] memory ticks, uint128 liquidity) external view returns (uint[] memory amounts);

    /// todo: remove, use only ^^^
    function getAmountsForLiquidity(address pool, int24 lowerTick, int24 upperTick, uint128 liquidity) external view returns (uint amount0, uint amount1);

    /// @notice Priced proportion of first pool asset
    /// @param pool Address of a pool supported by the adapter
    /// @return Proportion with 5 decimals precision. Max is 100_000, min is 0.
    function getProportion0(address pool) external view returns (uint);

    // todo implement getProportions
    // function getProportions(address pool) external view returns (uint[] memory);

    /// @notice Swap given tokenIn for tokenOut. Assume that tokenIn already sent to this contract.
    /// @param pool Address of a pool supported by the adapter
    /// @param tokenIn Token for sell
    /// @param tokenOut Token for buy
    /// @param recipient Recipient for tokenOut
    /// @param priceImpactTolerance Price impact tolerance. Must include fees at least. Denominator is 100_000.
    function swap(
        address pool,
        address tokenIn,
        address tokenOut,
        address recipient,
        uint priceImpactTolerance
    ) external;

    /// @notice Current price in pool without amount impact
    /// @param pool Address of a pool supported by the adapter
    /// @param tokenIn Token for sell
    /// @param tokenOut Token for buy
    /// @param amount Amount of tokenIn. For zero value provided amount 1.0 (10 ** decimals of tokenIn) will be used.
    function getPrice(
        address pool,
        address tokenIn,
        address tokenOut,
        uint amount
    ) external view returns (uint);

    /// @dev Initializer for proxied adapter
    function init(address platform) external;
}
