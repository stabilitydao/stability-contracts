// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title ZAP feature
interface IZap {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error StrategyNotSupported();
    error NotAllowedDexAggregator(address dexAggRouter);
    error AggSwapFailed(string reason);
    error Slippage(uint amountOut, uint minAmountOut);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           VIEW                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Request for swap amounts required to execute ZAP deposit
    /// @param vault Address of vault to invest
    /// @param tokenIn Input token address
    /// @param amountIn Amount of input token
    /// @return tokensOut Strategy assets
    /// @return swapAmounts Amounts for swap tokenIn -> asset
    function getDepositSwapAmounts(
        address vault,
        address tokenIn,
        uint amountIn
    ) external view returns (address[] memory tokensOut, uint[] memory swapAmounts);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           WRITE                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Allows to deposit into vault with swap tokenIn to vault assets
    /// @param vault Address of vault to invest
    /// @param tokenIn Input token address
    /// @param amountIn Amount of input token
    /// @param agg Address of aggregator
    /// @param swapData Swap data from 1inch API
    /// @param minSharesOut Minimum expected shares to be minted for user
    /// @param receiver Receiver of minted shares
    function deposit(
        address vault,
        address tokenIn,
        uint amountIn,
        address agg,
        bytes[] memory swapData,
        uint minSharesOut,
        address receiver
    ) external;

    /// @notice Allows to withdraw assets from vault with swap to exact tokenOut
    /// @param vault Address of vault to withdraw
    /// @param tokenOut Output token address
    /// @param agg Address of aggregator
    /// @param swapData Swap data from 1inch API
    /// @param sharesToBurn Shares to be burn (exchage) for assets
    /// @param minAmountOut Minimum expected amount of tokenOut to be received
    function withdraw(
        address vault,
        address tokenOut,
        address agg,
        bytes[] memory swapData,
        uint sharesToBurn,
        uint minAmountOut
    ) external;
}
