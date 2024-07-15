// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IYearnVault {
    /// @notice Get the full default queue currently set.
    /// @return The current default withdrawal queue.
    function get_default_queue() external view returns (address[] memory);

    /// @notice Get the price per share (pps) of the vault.
    /// @dev This value offers limited precision. Integrations that require
    ///      exact precision should use convertToAssets or convertToShares instead.
    /// @return The price per share.
    function pricePerShare() external view returns (uint);
}
