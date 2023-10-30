// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @dev Get price, swap, liquidity calculations. Used by strategies and swapper
/// @author Alien Deployer (https://github.com/a17)
interface IDexAdapter {
    event SwapInPool(
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

    function DEX_ADAPTER_ID() external view returns(string memory);

    function poolTokens(address pool) external view returns (address[] memory);

    function getLiquidityForAmounts(address pool, uint[] memory amounts) external view returns (uint liquidity, uint[] memory amountsConsumed);

    function getLiquidityForAmounts(address pool, uint[] memory amounts, int24[] memory ticks) external view returns (uint liquidity, uint[] memory amountsConsumed);

    function getAmountsForLiquidity(address pool, int24[] memory ticks, uint128 liquidity) external view returns (uint[] memory amounts);

    function getAmountsForLiquidity(address pool, int24 lowerTick, int24 upperTick, uint128 liquidity) external view returns (uint amount0, uint amount1);

    function getProportion0(address pool) external view returns (uint);

    function swap(
        address pool,
        address tokenIn,
        address tokenOut,
        address recipient,
        uint priceImpactTolerance
    ) external;

    function getPrice(
        address pool,
        address tokenIn,
        address tokenOut,
        uint amount
    ) external view returns (uint);

    function init(address platform) external;
}