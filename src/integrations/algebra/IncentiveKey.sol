// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

struct IncentiveKey {
    address rewardToken;
    address bonusRewardToken;
    address pool;
    uint256 startTime;
    uint256 endTime;
}