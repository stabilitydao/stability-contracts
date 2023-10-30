// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @dev Combining oracle and DeX spot prices
/// @author Alien Deployer (https://github.com/a17)
interface IPriceReader {
    /// @dev Price in USD with 18 decimals
    function getPrice(address asset) external view returns (uint price, bool trusted);

    function getAssetsPrice(address[] memory assets_, uint[] memory amounts_) external view returns (uint total, uint[] memory assetAmountPrice, bool trusted);

    function addAdapter(address adapter_) external;
}
