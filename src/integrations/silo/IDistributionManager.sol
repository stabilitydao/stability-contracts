// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IDistributionManager {
    struct AccruedRewards {
        uint amount;
        bytes32 programId;
        address rewardToken;
    }

    struct IncentiveProgramDetails {
        uint256 index;
        address rewardToken;
        uint104 emissionPerSecond;
        uint40 lastUpdateTimestamp;
        uint40 distributionEnd;
    }
}
