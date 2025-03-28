// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/BaseSetup.sol";
import "../base/UniversalTest.sol";

contract GammaUniswapV3MerklFarmStrategyTest is BaseSetup, UniversalTest {
    function testGUMF() public universalTest {
        buildingPayPerVaultTokenAmount = 1000e6;

        _addStrategy(3);
        _addStrategy(4);
        _addStrategy(5);
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
        deal(f.rewardAssets[0], currentStrategy, 1e17);
    }
}
