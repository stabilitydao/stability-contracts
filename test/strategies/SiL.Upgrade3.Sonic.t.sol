// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {SiloLeverageStrategy, IERC20} from "../../src/strategies/SiloLeverageStrategy.sol";
import {Factory} from "../../src/core/Factory.sol";
import {IProxy} from "../../src/interfaces/IProxy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";

contract SiLUpgrade3Test is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public constant STRATEGY = 0xfF9C35acDA4b136F71B1736B2BDFB5479f111C4A;
    address public vault;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(50605651); // Oct-14-2025 01:33:11 PM +UTC
        vault = IStrategy(STRATEGY).vault();
        _upgradeFactory(); // upgrade to Factory v2.0.0
    }

    function testSiLUpgrade3() public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address multisig = IPlatform(PLATFORM).multisig();

        // deploy new impl and upgrade
        address strategyImplementation = address(new SiloLeverageStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO_LEVERAGE, strategyImplementation);

        factory.upgradeStrategyProxy(STRATEGY);

        uint balanceWas = IERC20(vault).balanceOf(SonicConstantsLib.REVENUE_ROUTER);
        vm.prank(vault);
        IStrategy(STRATEGY).doHardWork();
        //console.log("got", (IERC20(vault).balanceOf(SonicConstantsLib.REVENUE_ROUTER) - balanceWas) / 1e18);
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
