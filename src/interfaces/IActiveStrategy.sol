// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @title Active strategy interface
/// @author Alien Deployer (https://github.com/a17)
interface IActiveStrategy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event Rebalanced(uint sharePrice, int loss);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error NotNeedRebalance();
    error NeedRebalance();
    error NotSupported();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Active strategy swaps assets during re-balancing though DeX aggregators
    function swaps() external view returns (bool);

    /// @notice Active strategy need to re-balance liquidity position now
    function needRebalance() external view returns (bool);

    /// @notice Active strategy need to re-balance liquidity position now with swaps of assets
    /// @return need Need re-balancing
    /// @return swapAssetIn Assets IN for swap
    /// @return swapAssetOut Asset OUT for swap
    /// @return swapAmount Amounts for swaps
    function needRebalanceWithSwap()
        external
        view
        returns (bool need, address[] memory swapAssetIn, address[] memory swapAssetOut, uint[] memory swapAmount);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Execute re-balancing of active strategy
    function rebalance() external;

    /// @notice Execute re-balancing of active strategy with swaps by DeX aggregator
    /// @param swapAssetIn Assets IN for swap
    /// @param swapAssetOut Asset OUT for swap
    /// @param swapAmount Amounts for swaps
    /// @param swapData Swap transactions input data for agg.call
    /// @param agg Address of DeX aggregator router allowed to use in the platform
    function rebalanceWithSwap(
        address[] memory swapAssetIn,
        address[] memory swapAssetOut,
        uint[] memory swapAmount,
        bytes[] memory swapData,
        address agg
    ) external;
}
