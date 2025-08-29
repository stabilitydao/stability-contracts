// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib, IFactory} from "../base/UniversalTest.sol";

contract GammaUniswapV3MerklFarmStrategyTestSonic is SonicSetup, UniversalTest {
    constructor() {
        //vm.rollFork(5169000); // Jan-23-2025 07:56:29 PM
    }

    function testGUMF() public universalTest {
        _addStrategy(18);
        _addStrategy(19);
        _addStrategy(20);
        _addStrategy(21);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.GAMMA_UNISWAPV3_MERKL_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }

    function _preHardWork(uint farmId) internal override {
        IFactory.Farm memory f = factory.farm(farmId);
        deal(f.rewardAssets[0], currentStrategy, 1e18);
    }
}
