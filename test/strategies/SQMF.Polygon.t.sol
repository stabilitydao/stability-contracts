// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";
import "../../src/integrations/steer/IMultiPositionManager.sol";

contract SteerQuickSwapMerklFarmStrategyTest is PolygonSetup, UniversalTest {
    constructor() {
        vm.rollFork(55600000); // Apr-08-2024
    }

    function testSQMF() public universalTest {
        _addStrategy(41);
        _addStrategy(42);
        // _addStrategy(43);
        _addStrategy(45);
        _addStrategy(44);
        _addStrategy(46);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.STEER_QUICKSWAP_MERKL_FARM,
                pool: address(0),
                farmId: farmId,
                underlying: address(0)
            })
        );
    }

    function _preHardWork() internal override {
        deal(PolygonLib.TOKEN_QUICK, currentStrategy, 10e18);
    }
}
