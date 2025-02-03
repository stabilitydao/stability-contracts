// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/SonicSetup.sol";
import "../base/UniversalTest.sol";

contract SiloFarmStrategyTest is SonicSetup, UniversalTest {
    function testSiFSonic() public universalTest {
        _addStrategy(22);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_FARM,
                pool: address(0),
                farmId: farmId, // chains/SonicLib.sol
                underlying: address(0)
            })
        );
    }
}
