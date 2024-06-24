// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IFeedRegistryInterface {
    function decimals(address base, address quote) external view returns (uint8);

    function latestRoundData(
        address base,
        address quote
    ) external view returns (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound);
}
