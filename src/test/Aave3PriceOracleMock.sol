// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAavePriceOracle} from "../integrations/aave/IAavePriceOracle.sol";
import {IAaveAddressProvider} from "../integrations/aave/IAaveAddressProvider.sol";

contract Aave3PriceOracleMock is IAavePriceOracle {
    IAavePriceOracle private _aavePriceOracle;

    mapping(address => address) private _sources;
    mapping(address => uint) private _prices;

    constructor(address aavePriceOracle_) {
        _aavePriceOracle = IAavePriceOracle(aavePriceOracle_);
    }

    //region ---------------------------------- Setup

    function setAssetPrice(address asset_, uint values_) external {
        _prices[asset_] = values_;
    }

    function setPrices(address[] memory assets_, uint[] memory values_) external {
        for (uint i = 0; i < assets_.length; ++i) {
            _prices[assets_[i]] = values_[i];
        }
    }

    //endregion ---------------------------------- Setup

    // add this to be excluded from coverage report
    function test() public {}

    //region ---------------------------------- IAavePriceOracle

    /// @notice Returns the PoolAddressesProvider
    /// @return The address of the PoolAddressesProvider contract
    function ADDRESSES_PROVIDER() external view override returns (address) {
        return IAavePriceOracle(_aavePriceOracle).ADDRESSES_PROVIDER();
    }

    /// @notice Returns the base currency address
    /// @dev Address 0x0 is reserved for USD as base currency.
    /// @return Returns the base currency address.
    function BASE_CURRENCY() external view override returns (address) {
        return _aavePriceOracle.BASE_CURRENCY();
    }

    /// @notice Returns the base currency unit
    /// @dev 1 ether for ETH, 1e8 for USD.
    /// @return Returns the base currency unit.
    function BASE_CURRENCY_UNIT() external view override returns (uint) {
        return _aavePriceOracle.BASE_CURRENCY_UNIT();
    }

    /// @notice Returns the asset price in the base currency
    /// @param asset The address of the asset
    /// @return The price of the asset
    function getAssetPrice(address asset) external view override returns (uint) {
        uint updatedPrice = _prices[asset];
        return updatedPrice == 0 ? _aavePriceOracle.getAssetPrice(asset) : updatedPrice;
    }

    /// @notice Returns a list of prices from a list of assets addresses
    /// @param assets The list of assets addresses
    /// @return The prices of the given assets
    function getAssetsPrices(address[] memory assets) external view override returns (uint[] memory) {
        uint[] memory dest = new uint[](assets.length);
        for (uint i = 0; i < assets.length; ++i) {
            dest[i] = _prices[assets[i]];
        }
        return dest;
    }

    /// @notice Returns the address of the fallback oracle
    /// @return The address of the fallback oracle
    function getFallbackOracle() external view override returns (address) {
        return _aavePriceOracle.getFallbackOracle();
    }

    /// @notice Returns the address of the source for an asset address
    /// @param asset The address of the asset
    /// @return The address of the source
    function getSourceOfAsset(address asset) external view override returns (address) {
        return _sources[asset];
    }

    function setAssetSources(address[] memory assets, address[] memory sources) external override {
        for (uint i = 0; i < assets.length; ++i) {
            _sources[assets[i]] = sources[i];
        }
    }

    function setFallbackOracle(address fallbackOracle) external override {
        _aavePriceOracle.setFallbackOracle(fallbackOracle);
    }

    //endregion ---------------------------------- IAavePriceOracle
}
