// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IAggregatorInterfaceMinimal} from "../integrations/chainlink/IAggregatorInterfaceMinimal.sol";

interface IBridgedPriceOracle is IAggregatorInterfaceMinimal {
    error InvalidSender();
    error InvalidMessageFormat();

    /// @notice Emitted when price is updated
    event PriceUpdated(uint priceUsd18, uint priceTimestamp);
    event TrustedSenderUpdated(address trustedSender, uint[] endpointIds, bool isTrusted);

    /// @notice Returns the latest price in USD with 18 decimals
    /// @return price Price in USD with 18 decimals
    /// @return priceTimestamp Timestamp of the price - moment of price update in source PriceAggregator
    function getPriceUsd18() external view returns (uint price, uint priceTimestamp);

    /// @notice True if the given sender is trusted for a specific chain
    /// @param srcEid Source chain endpoint ID, see https://docs.layerzero.network/v2/concepts/glossary#endpoint-id
    /// @param sender Address of the sender on the source chain
    function isTrustedSender(address sender, uint srcEid) external view returns (bool);

    /// @notice True if the given sender is trusted for a specific chain
    /// @param srcEids Source chain endpoint IDs, see https://docs.layerzero.network/v2/concepts/glossary#endpoint-id
    /// @param sender Address of the sender on the source chain
    /// @param trusted True to set as trusted, false to remove from trusted
    function setTrustedSender(address sender, uint[] memory srcEids, bool trusted) external;
}
