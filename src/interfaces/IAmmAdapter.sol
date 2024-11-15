// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @dev Get price, swap, liquidity calculations. Used by strategies and swapper
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
interface IAmmAdapter is IERC165 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error PriceIncreased();
    error WrongCallbackAmount();
    error NotSupportedByCAMM();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event SwapInPool(
        address pool,
        address tokenIn,
        address tokenOut,
        address recipient,
        uint priceImpactTolerance,
        uint amountIn,
        uint amountOut
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct SwapCallbackData {
        address tokenIn;
        uint amount;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice String ID of the adapter
    function ammAdapterId() external view returns (string memory);

    /// @notice Tokens of a pool supported by the adapter
    function poolTokens(address pool) external view returns (address[] memory);

    /// @notice Computes the maximum amount of liquidity received for given amounts of pool assets and the current
    /// pool price.
    /// This function signature can be used only for non-concentrated AMMs.
    /// @param pool Address of a pool supported by the adapter
    /// @param amounts Amounts of pool assets
    /// @return liquidity Liquidity out value
    /// @return amountsConsumed Amounts of consumed assets when providing liquidity
    function getLiquidityForAmounts(
        address pool,
        uint[] memory amounts
    ) external view returns (uint liquidity, uint[] memory amountsConsumed);

    /// @notice Priced proportions of pool assets
    /// @param pool Address of a pool supported by the adapter
    /// @return Proportions with 18 decimals precision. Max is 1e18, min is 0.
    function getProportions(address pool) external view returns (uint[] memory);

    /// @notice Current price in pool without amount impact
    /// @param pool Address of a pool supported by the adapter
    /// @param tokenIn Token for sell
    /// @param tokenOut Token for buy
    /// @param amount Amount of tokenIn. For zero value provided amount 1.0 (10 ** decimals of tokenIn) will be used.
    /// @return Amount of tokenOut with tokenOut decimals precision
    function getPrice(address pool, address tokenIn, address tokenOut, uint amount) external view returns (uint);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

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

    /// @dev Initializer for proxied adapter
    function init(address platform) external;
}
