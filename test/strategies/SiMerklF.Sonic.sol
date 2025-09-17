// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {SonicLib, SonicConstantsLib} from "../../chains/sonic/SonicLib.sol";

contract SiloMerklFarmStrategySonicTest is SonicSetup, UniversalTest {
    constructor() {
        vm.rollFork(47151219); // Sep-17-2025 12:22:57 PM +UTC
    }

    function testSiFSonic() public universalTest {
        _addStrategy(66);
        _addStrategy(67);
    }

    //region -------------------------------- Universal test overrides
    function _preHardWork() internal override {
        // emulate Merkl-rewards
        deal(SonicConstantsLib.TOKEN_USDC, currentStrategy, 1e6);
        deal(SonicConstantsLib.TOKEN_xSILO, currentStrategy, 100e18);
    }
    //endregion -------------------------------- Universal test overrides

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_MERKL_FARM,
                pool: address(0),
                farmId: farmId, // chains/sonic/SonicLib.sol
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
