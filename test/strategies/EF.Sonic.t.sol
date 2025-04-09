// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import "../../chains/sonic/SonicLib.sol";
import "../base/UniversalTest.sol";

contract EqualizerFarmStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        allowZeroApr = true;
        makePoolVolumePriceImpactTolerance = 30_000;
    }

    function testEF() public universalTest {
        _addStrategy(2);
        _addStrategy(3);
        _addStrategy(4);
        _addStrategy(5);
        //_addStrategy(7);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.EQUALIZER_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
