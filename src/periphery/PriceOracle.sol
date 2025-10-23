// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAggregatorInterfaceMinimal} from "../integrations/chainlink/IAggregatorInterfaceMinimal.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IPriceAggregator} from "../interfaces/IPriceAggregator.sol";

/// @title Chainlink-compatible vault trusted price feed
/// @notice Allow to get prices from price aggregator through Chainlink interface
/// @author Omriss (https://github.com/omriss)
contract PriceOracle is IAggregatorInterfaceMinimal {
    /// @notice Address of the vault or asset
    /// forge-lint: disable-next-line(screaming-snake-case-immutable)
    address public immutable entity;

    /// @notice Address of price aggregator
    /// forge-lint: disable-next-line(screaming-snake-case-immutable)
    IPriceAggregator public immutable priceAggregator;

    /// @param entity_ Address of the vault or asset
    constructor(address entity_, address priceAggregator_) {
        // slither-disable-next-line missing-zero-check
        entity = entity_;

        // slither-disable-next-line missing-zero-check
        priceAggregator = IPriceAggregator(priceAggregator_);
    }

    /// @inheritdoc IAggregatorInterfaceMinimal
    function latestAnswer() external view returns (int) {
        // assume here that price aggregator always returns price in USD with 18 decimals

        // slither-disable-next-line unused-return
        (uint price,,) = priceAggregator.price(entity);

        return int(price / 10 ** 10);
    }

    /// @inheritdoc IAggregatorInterfaceMinimal
    function decimals() external pure returns (uint8) {
        return 8;
    }
}
