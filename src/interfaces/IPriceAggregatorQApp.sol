// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {MessagingFee} from "@layerzerolabs/oapp-evm-upgradeable/contracts/oapp/OAppUpgradeable.sol";

interface IPriceAggregatorQApp {
    error NotWhitelisted();
    error UnsupportedOperation();

    event PriceUpdated(uint destEid, uint priceUsd18, uint priceTimestamp);
    event ChangeWhitelist(address caller, bool whitelisted);
    event SendPriceMessage(uint destEid, uint priceUsd18, uint priceTimestamp);

    /// @notice Address of the entity (vault or asset) to get price for
    function entity() external view returns (address);

    /// @notice True if the given caller is whitelisted to request price updates
    function isWhitelisted(address caller) external view returns (bool);

    /// @notice Change whitelist status for the given caller
    /// @param caller Address of the caller
    /// @param whitelisted True to add to whitelist, false to remove from whitelist
    function changeWhitelist(address caller, bool whitelisted) external;

    /// @notice Quote the gas needed to pay for sending price message to the given destination chain endpoint ID.
    /// The message is generated internally as a packet of price value and timestamp taken from the price aggregator
    /// @param dstEid_ Destination chain endpoint ID, see https://docs.layerzero.network/v2/concepts/glossary#endpoint-id
    /// @param options_ Additional options for the message.
    /// @param payInLzToken_ Whether to return fee in ZRO token.
    /// @return fee A `MessagingFee` struct containing the calculated gas fee in either the native token or ZRO token.
    function quotePriceMessage(
        uint32 dstEid_,
        bytes memory options_,
        bool payInLzToken_
    ) external view returns (MessagingFee memory fee);

    /// @notice Send price message to a remote BridgedPriceOracle on another chain.
    /// The message is generated internally as a packet of price value and timestamp taken from the price aggregator
    /// @param dstEid_ Destination chain endpoint ID, see https://docs.layerzero.network/v2/concepts/glossary#endpoint-id
    /// @param options_ Additional options for the message.
    /// @param fee_ A `MessagingFee` struct containing the gas fee to be paid
    function sendPriceMessage(uint32 dstEid_, bytes memory options_, MessagingFee memory fee_) external payable;
}
