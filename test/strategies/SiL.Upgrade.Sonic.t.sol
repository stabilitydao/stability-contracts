// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {SiloLeverageStrategy} from "../../src/strategies/SiloLeverageStrategy.sol";
import {Factory} from "../../src/core/Factory.sol";
import {IProxy} from "../../src/interfaces/IProxy.sol";

contract SiLUpgradeTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STRATEGY = 0xfF9C35acDA4b136F71B1736B2BDFB5479f111C4A;
    address public vault;

    uint public constant FORK_BLOCK = 16296000; // Mar-27-2025 08:48:46 AM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        vault = IStrategy(STRATEGY).vault();
        _upgradeFactory(); // upgrade to Factory v2.0.0
    }

    function testSiLUpgrade() public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address multisig = IPlatform(PLATFORM).multisig();

        // deploy new impl and upgrade
        address strategyImplementation = address(new SiloLeverageStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO_LEVERAGE, strategyImplementation);

        factory.upgradeStrategyProxy(STRATEGY);

        //uint balanceWas = IERC20(vault).balanceOf(multisig);
        vm.prank(vault);
        IStrategy(STRATEGY).doHardWork();
        //console.log('got', IERC20(vault).balanceOf(multisig) - balanceWas);
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
