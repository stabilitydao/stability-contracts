// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IDistributionManager} from "./IDistributionManager.sol";

interface ISiloIncentivesController is IDistributionManager {
    /**
     * @dev Claims reward for an user to the desired address, on all the assets of the lending pool,
     * accumulating the pending rewards
     * @param _to Address that will be receiving the rewards
     * @return accruedRewards
     */
    function claimRewards(address _to) external returns (AccruedRewards[] memory accruedRewards);

    /**
     * @dev Claims reward for an user to the desired address, on all the assets of the lending pool,
     * accumulating the pending rewards
     * @param _to Address that will be receiving the rewards
     * @param _programNames The incentives program names
     * @return accruedRewards
     */
    function claimRewards(
        address _to,
        string[] calldata _programNames
    ) external returns (AccruedRewards[] memory accruedRewards);

    function SHARE_TOKEN() external view returns (address);
}
