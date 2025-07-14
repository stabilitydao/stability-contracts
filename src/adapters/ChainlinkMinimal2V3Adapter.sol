// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../integrations/chainlink/IAggregatorInterfaceMinimal.sol";
import "../integrations/chainlink/IAggregatorV3Interface.sol";

/// @notice Convert IAggregatorInterfaceMinimal to IAggregatorV3Interface
contract ChainlinkMinimal2V3Adapter is IAggregatorV3Interface {
    address public immutable aggregatorMinimal;

    constructor(address aggregatorMinimal_) {
        aggregatorMinimal = aggregatorMinimal_;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound)
    {
        return (
            0, // roundId is not available in IAggregatorInterfaceMinimal
            IAggregatorInterfaceMinimal(aggregatorMinimal).latestAnswer(),
            0, // startedAt is not available in IAggregatorInterfaceMinimal
            block.timestamp, // updatedAt is set to current block timestamp
            0 // answeredInRound is not available in IAggregatorInterfaceMinimal
        );
    }
}
