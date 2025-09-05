// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// import {console} from "forge-std/Test.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";

contract SwapXFarmStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        depositedSharesCheckDelimiter = 100;
        makePoolVolume = false;
        // makePoolVolumePriceImpactTolerance = 10_000;
    }

    function testSF() public universalTest {
        // _addStrategy(14);
        _addStrategy(15);
        // _addStrategy(16);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.SWAPX_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
