// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";

contract SiloMerklFarmStrategySonicTest is SonicSetup, UniversalTest {
    uint internal constant FARM_UID_66 = 66;
    uint internal constant FARM_UID_67 = 67;

    constructor() {
        vm.rollFork(47151219); // Sep-17-2025 12:22:57 PM +UTC
    }

    function testSiFSonic() public universalTest {
        _addStrategy(FARM_UID_66);
        _addStrategy(FARM_UID_67);
    }

    //region -------------------------------- Universal test overrides
    function _preHardWork() internal override {
        // emulate Merkl-rewards
        deal(SonicConstantsLib.TOKEN_USDC, currentStrategy, 1e6);
        deal(SonicConstantsLib.TOKEN_XSILO, currentStrategy, 100e18);
    }

    /// @notice Real farms don't use gauges at this moment
    /// But we need to test gauge-related code paths, so let's change params of single farm and add fake gauge
    function _preDeposit() internal override {
        address multisig = IPlatform(platform).multisig();
        {
            IFarmingStrategy strategy = IFarmingStrategy(currentStrategy);
            if (strategy.farmId() == FARM_UID_66) {
                // let's change farm params: add fake gauge to be sure
                // that the gauge-related code is tested
                IFactory factory = IFactory(IPlatform(platform).factory());
                IFactory.Farm memory f = factory.farm(FARM_UID_66);
                assertEq(f.addresses[2], address(0), "gauge must be empty initially");
                f.addresses[2] = SonicConstantsLib.SILO_GAUGE_WS_054; // actual gauge doesn't matter

                vm.prank(multisig);
                factory.updateFarm(FARM_UID_66, f);
            }
        }

        // -------------------------- test new getSpecificName
        {
            IStrategy strategy = IStrategy(currentStrategy);
            if (IFarmingStrategy(currentStrategy).farmId() == FARM_UID_66) {
                (string memory name,) = strategy.getSpecificName();
                assertEq(name, "smsUSD, 138", "default getSpecificName must be correct");

                vm.prank(multisig);
                strategy.setSpecificName("aaaA");

                (name,) = strategy.getSpecificName();
                assertEq(name, "aaaA", "explicit specific name must be correct");

                vm.prank(multisig);
                strategy.setSpecificName("");

                (name,) = strategy.getSpecificName();
                assertEq(name, "smsUSD, 138", "default getSpecificName must be correct after reset");
            }

            if (IFarmingStrategy(currentStrategy).farmId() == FARM_UID_67) {
                (string memory name,) = strategy.getSpecificName();
                assertEq(name, "PT-smsUSD-30OCT2025, 141", "default getSpecificName must be correct 2");

                vm.prank(multisig);
                strategy.setSpecificName("bbbB");

                (name,) = strategy.getSpecificName();
                assertEq(name, "bbbB", "explicit specific name must be correct 2");

                vm.prank(multisig);
                strategy.setSpecificName("");

                (name,) = strategy.getSpecificName();
                assertEq(name, "PT-smsUSD-30OCT2025, 141", "default getSpecificName must be correct after reset 2");
            }
        }
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
