// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev Adapter for reading oracle prices
/// @author Alien Deployer (https://github.com/a17)
interface IOracleAdapter {
    /// @notice Asset USD price
    /// @param asset Address of supported asset
    /// @return price USD price of 1.0 asset with 18 decimals precision
    /// @return timestamp Timestamp of last price update
    function getPrice(address asset) external view returns (uint price, uint timestamp);

    /// @notice Get all supported assets prices
    /// @return assets_ Addresses of assets
    /// @return prices USD prices of 1.0 asset with 18 decimals precision
    /// @return timestamps Timestamps of last price update
    function getAllPrices()
        external
        view
        returns (address[] memory assets_, uint[] memory prices, uint[] memory timestamps);

    /// @notice Get all supported assets in the adapter
    function assets() external view returns (address[] memory);
}
