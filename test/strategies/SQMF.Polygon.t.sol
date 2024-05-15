// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";
import "../../src/integrations/steer/IMultiPositionManager.sol";

contract SteerQuickSwapMerklFarmStrategyTest is PolygonSetup, UniversalTest {
    constructor() {}

    function testSQMF() public universalTest {
        specialDepositAmounts.push(11838);
        specialDepositAmounts.push(11971);

        // add farms for testing
        _addStrategy(38);
        _addStrategy(39);
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
        deal(PolygonLib.TOKEN_dQUICK, currentStrategy, 10e18);
    }
}
