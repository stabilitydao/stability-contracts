// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IAggregatorInterfaceMinimal} from "../integrations/chainlink/IAggregatorInterfaceMinimal.sol";

interface IBridgedPriceOracle is IAggregatorInterfaceMinimal {
    error InvalidSender();
    error InvalidMessageFormat();

    /// @notice Emitted when price is updated
    event PriceUpdated(uint priceUsd18, uint priceTimestamp);
    event TrustedSenderUpdated(address trustedSender, uint srcEid, bool isTrusted);

    /// @notice Returns the latest price in USD with 18 decimals
    /// @return price Price in USD with 18 decimals
    /// @return priceTimestamp Timestamp of the price - moment of price update in source PriceAggregator
    function getPriceUsd18() external view returns (uint price, uint priceTimestamp);
}
