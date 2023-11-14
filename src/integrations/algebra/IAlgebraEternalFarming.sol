// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./IncentiveKey.sol";

interface IAlgebraEternalFarming {
    /// @notice reward amounts can be outdated, actual amounts could be obtained via static call of `collectRewards` in FarmingCenter
    function getRewardInfo(
        IncentiveKey memory key,
        uint256 tokenId
    ) external view returns (uint256 reward, uint256 bonusReward);
}