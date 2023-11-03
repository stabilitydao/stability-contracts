// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @dev Combining oracle and DeX spot prices
/// @author Alien Deployer (https://github.com/a17)
interface IPriceReader {
    /// @notice Price of asset
    /// @dev Price of 1.0 amount of asset in USD
    /// @param asset Address of token
    /// @return price USD price with 18 decimals
    /// @return trusted Price from oracle
    function getPrice(address asset) external view returns (uint price, bool trusted);

    /// @notice Prices of specified amounts of assets
    
    function getAssetsPrice(address[] memory assets_, uint[] memory amounts_) external view returns (uint total, uint[] memory assetAmountPrice, bool trusted);

    function addAdapter(address adapter_) external;
}
