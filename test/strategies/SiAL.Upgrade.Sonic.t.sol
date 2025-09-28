// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {SiloAdvancedLeverageStrategy} from "../../src/strategies/SiloAdvancedLeverageStrategy.sol";
import {Factory} from "../../src/core/Factory.sol";
import {IProxy} from "../../src/interfaces/IProxy.sol";

contract SiALUpgradeTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STRATEGY = 0xDf077C7ffFa6B140d76dE75c792F49D6cB62AE19;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(13624880); // Mar-14-2025 07:49:27 AM +UTC

        _upgradeFactory(); // upgrade to Factory v2.0.0
    }

    function testSiALUpgrade() public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address multisig = IPlatform(PLATFORM).multisig();

        // deploy new impl and upgrade
        address strategyImplementation = address(new SiloAdvancedLeverageStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO_ADVANCED_LEVERAGE, strategyImplementation);

        factory.upgradeStrategyProxy(STRATEGY);

        (uint[] memory params, address[] memory addresses) =
            SiloAdvancedLeverageStrategy(payable(STRATEGY)).getUniversalParams();
        //console.log(params[0]);
        params[0] = 90_00;
        vm.prank(multisig);
        SiloAdvancedLeverageStrategy(payable(STRATEGY)).setUniversalParams(params, addresses);
        (params, addresses) = SiloAdvancedLeverageStrategy(payable(STRATEGY)).getUniversalParams();
        assertEq(params[0], 90_00);
    }

    function _upgradeFactory() internal {
        // deploy new Factory implementation
        address newImpl = address(new Factory());

        // get the proxy address for the factory
        address factoryProxy = address(IPlatform(PLATFORM).factory());

        // prank as the platform because only it can upgrade
        vm.prank(PLATFORM);
        IProxy(factoryProxy).upgrade(newImpl);
    }
}
