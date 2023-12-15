// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../integrations/chainlink/IAggregatorV3Interface.sol";

contract MockAggregatorV3Interface is IAggregatorV3Interface {
    int private _answer;
    uint private _updatedAt;

    // add this to be excluded from coverage report
    function test() public {}

    function setAnswer(int answer_) external {
        _answer = answer_;
    }

    function setUpdatedAt(uint updatedAt_) external {
        _updatedAt = updatedAt_;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound)
    {
        return (0, _answer, _updatedAt, _updatedAt, 0);
    }
}
