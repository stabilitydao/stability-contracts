pragma solidity ^0.8.20;

/// @notice Aave price oracle for AAVE 3.0.2
interface IAavePriceOracle {

    function ADDRESSES_PROVIDER() external view returns (address);

    function BASE_CURRENCY() external view returns (address);

    function BASE_CURRENCY_UNIT() external view returns (uint256);

    function getAssetPrice(address asset) external view returns (uint256);

    function getAssetsPrices(address[] memory assets)
    external
    view
    returns (uint256[] memory);

    function getFallbackOracle() external view returns (address);

    function getSourceOfAsset(address asset) external view returns (address);

    function setAssetSources(address[] memory assets, address[] memory sources)
    external;

    function setFallbackOracle(address fallbackOracle) external;
}

