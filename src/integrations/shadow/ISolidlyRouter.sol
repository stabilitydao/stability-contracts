// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ISolidlyRouter {
    /// @notice calculates the CREATE2 address for a pair without making any external calls
    /// @param tokenA the address of tokenA
    /// @param tokenB the address of tokenB
    /// @param stable if the pair is using the stable curve
    /// @return pair address of the pair
    function pairFor(address tokenA, address tokenB, bool stable) external view returns (address pair);

    /// @notice performs calculations to determine the expected state when adding liquidity
    /// @param tokenA the address of tokenA
    /// @param tokenB the address of tokenB
    /// @param stable if the pair is using the stable curve
    /// @param amountADesired amount of tokenA desired to be added
    /// @param amountBDesired amount of tokenB desired to be added
    /// @return amountA amount of tokenA added
    /// @return amountB amount of tokenB added
    /// @return liquidity liquidity value added
    function quoteAddLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountADesired,
        uint amountBDesired
    ) external view returns (uint amountA, uint amountB, uint liquidity);

    /// @param tokenA the address of tokenA
    /// @param tokenB the address of tokenB
    /// @param stable if the pair is using the stable curve
    /// @param liquidity liquidity value to remove
    /// @return amountA amount of tokenA removed
    /// @return amountB amount of tokenB removed
    function quoteRemoveLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint liquidity
    ) external view returns (uint amountA, uint amountB);

    /// @param tokenA the address of tokenA
    /// @param tokenB the address of tokenB
    /// @param stable if the pair is using the stable curve
    /// @param amountADesired amount of tokenA desired to be added
    /// @param amountBDesired amount of tokenB desired to be added
    /// @param amountAMin slippage for tokenA calculated from this param
    /// @param amountBMin slippage for tokenB calculated from this param
    /// @param to the address the liquidity tokens should be minted to
    /// @param deadline timestamp deadline
    /// @return amountA amount of tokenA used
    /// @return amountB amount of tokenB used
    /// @return liquidity amount of liquidity minted
    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    /// @param token the address of token
    /// @param stable if the pair is using the stable curve
    /// @param amountTokenDesired desired amount for token
    /// @param amountTokenMin slippage for token
    /// @param amountETHMin minimum amount of ETH added (slippage)
    /// @param to the address the liquidity tokens should be minted to
    /// @param deadline timestamp deadline
    /// @return amountToken amount of the token used
    /// @return amountETH amount of ETH used
    /// @return liquidity amount of liquidity minted
    function addLiquidityETH(
        address token,
        bool stable,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    /// @param tokenA the address of tokenA
    /// @param tokenB the address of tokenB
    /// @param stable if the pair is using the stable curve
    /// @param amountADesired amount of tokenA desired to be added
    /// @param amountBDesired amount of tokenB desired to be added
    /// @param amountAMin slippage for tokenA calculated from this param
    /// @param amountBMin slippage for tokenB calculated from this param
    /// @param to the address the liquidity tokens should be minted to
    /// @param deadline timestamp deadline
    /// @return amountA amount of tokenA used
    /// @return amountB amount of tokenB used
    /// @return liquidity amount of liquidity minted
    function addLiquidityAndStake(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    /// @notice adds liquidity to a legacy pair using ETH, and stakes it into a gauge on "to's" behalf
    /// @param token the address of token
    /// @param stable if the pair is using the stable curve
    /// @param amountTokenDesired amount of token to be used
    /// @param amountTokenMin slippage of token
    /// @param amountETHMin slippage of ETH
    /// @param to the address the liquidity tokens should be minted to
    /// @param deadline timestamp deadline
    /// @return amountA amount of tokenA used
    /// @return amountB amount of tokenB used
    /// @return liquidity amount of liquidity minted
    function addLiquidityETHAndStake(
        address token,
        bool stable,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountA, uint amountB, uint liquidity);

    /// @param tokenA the address of tokenA
    /// @param tokenB the address of tokenB
    /// @param stable if the pair is using the stable curve
    /// @param liquidity amount of LP tokens to remove
    /// @param amountAMin slippage of tokenA
    /// @param amountBMin slippage of tokenB
    /// @param to the address the liquidity tokens should be minted to
    /// @param deadline timestamp deadline
    /// @return amountA amount of tokenA used
    /// @return amountB amount of tokenB used
    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    /// @param token address of the token
    /// @param stable if the pair is using the stable curve
    /// @param liquidity liquidity tokens to remove
    /// @param amountTokenMin slippage of token
    /// @param amountETHMin slippage of ETH
    /// @param to the address the liquidity tokens should be minted to
    /// @param deadline timestamp deadline
    /// @return amountToken amount of token used
    /// @return amountETH amount of ETH used
    function removeLiquidityETH(
        address token,
        bool stable,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
}
