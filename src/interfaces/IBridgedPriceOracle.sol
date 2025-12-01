// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IAggregatorInterfaceMinimal} from "../integrations/chainlink/IAggregatorInterfaceMinimal.sol";

interface IBridgedPriceOracle is IAggregatorInterfaceMinimal {
    error InvalidMessageFormat();

    /// @notice Emitted when price is updated
    event PriceUpdated(uint priceUsd18, uint priceTimestamp);
    event PriceUpdateSkipped(uint priceUsd18, uint priceTimestamp);

    /// @notice Returns the latest price in USD with 18 decimals
    /// @return price Price in USD with 18 decimals
    /// @return priceTimestamp Timestamp of the price - moment of price update in source PriceAggregator
    function getPriceUsd18() external view returns (uint price, uint priceTimestamp);

    /// @notice Token for which this oracle provides price
    function tokenSymbol() external view returns (string memory);

    /// @notice Initialize with platform and token symbol
    function initialize(address platform_, string memory tokenSymbol_) external;
}
