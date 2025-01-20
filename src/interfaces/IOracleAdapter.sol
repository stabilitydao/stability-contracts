// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev Adapter for reading oracle prices
/// @author Alien Deployer (https://github.com/a17)
interface IOracleAdapter {

    event NewPriceFeeds(address[] assets, address[] priceFeeds);
    event UpdatedPriceFeed(address asset, address priceFeed);
    event RemovedPriceFeeds(address[] assets);

    /// @notice Add price feed to get prices
    /// Only operator can call this
    /// @param assets_ Addresses of supported assets
    /// @param priceFeeds_ Addresses of price feeds
    function addPriceFeeds(address[] memory assets_, address[] memory priceFeeds_) external;

    /// @notice Update price feed address for asset
    /// Only governance or multisig can call this
    /// @param asset Address of supported asset
    /// @param priceFeed Address of price feed for asset
    function updatePriceFeed(address asset, address priceFeed) external;

    /// @notice Remove price feeds
    /// Only governance or multisig can call this
    /// @param assets_ Addresses of supported assets
    function removePriceFeeds(address[] memory assets_) external;

    /// @notice Price feeds mapping
    /// @param asset Address of supported asset
    /// @param priceFeed Address of price feed for asset
    function priceFeeds(address asset) external view returns (address priceFeed);

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
