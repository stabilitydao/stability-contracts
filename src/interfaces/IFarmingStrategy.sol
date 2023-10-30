// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @dev This interface need for front-end and tests for interacting with farming strategies
interface IFarmingStrategy {
    event RewardsClaimed(uint[] amounts);

    function farmId() external view returns (uint);

    function canFarm() external view returns (bool);
}
