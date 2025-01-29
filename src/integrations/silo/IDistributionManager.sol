// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IDistributionManager {
    struct AccruedRewards {
        uint256 amount;
        bytes32 programId;
        address rewardToken;
    }
}
