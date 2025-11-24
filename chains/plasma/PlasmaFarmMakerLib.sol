// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {PlasmaConstantsLib} from "./PlasmaConstantsLib.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {SiloManagedMerklFarmStrategy} from "../../src/strategies/SiloManagedMerklFarmStrategy.sol";

library PlasmaFarmMakerLib {
    function _makeAaveMerklFarm(address atoken) internal pure returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.strategyLogicId = StrategyIdLib.AAVE_MERKL_FARM;

        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = PlasmaConstantsLib.TOKEN_WXPL;

        farm.addresses = new address[](1);
        farm.addresses[0] = atoken;

        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function testFarmMakerLib() external {}
}