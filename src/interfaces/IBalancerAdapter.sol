// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IBalancerAdapter {
    /// @dev Add BalancerHelpers contract address
    function setupHelpers(address balancerHelpers) external;

    /// @notice Computes the maximum amount of liquidity received for given amounts of pool assets and the current
    /// pool price.
    /// This function signature can be used only for non-concentrated AMMs.
    /// @dev This method used instead getLiquidityForAmounts because BalancerHelpers use queryJoin
    /// write method. Can be used off-chain by callStatic.
    /// @param pool Address of a pool supported by the adapter
    /// @param amounts Amounts of pool assets
    /// @return liquidity Liquidity out value
    /// @return amountsConsumed Amounts of consumed assets when providing liquidity
    function getLiquidityForAmountsWrite(
        address pool,
        uint[] memory amounts
    ) external returns (uint liquidity, uint[] memory amountsConsumed);
}
