// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IDistributionManager} from "./IDistributionManager.sol";

interface ISiloIncentivesController is IDistributionManager {
    
    function claimRewards(
        address _to
    ) external returns (AccruedRewards[] memory accruedRewards);

    function claimRewards(
        address _to,
        string[] calldata _programNames
    ) external returns (AccruedRewards[] memory accruedRewards);
}
