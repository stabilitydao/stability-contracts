// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ALMShadowFarmStrategy} from "../../src/strategies/ALMShadowFarmStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {Factory} from "../../src/core/Factory.sol";
import {IProxy} from "../../src/interfaces/IProxy.sol";

contract ASFUpgrade2Test is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STRATEGY = 0xa413658211DECDf44171ED6d8E37F7eDCD637117;
    address public vault;
    address public multisig;
    IFactory public factory;

    uint internal constant FORK_BLOCK = 6420000; // Feb-03-2025 04:09:12 PM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        vault = IStrategy(STRATEGY).vault();
        multisig = IPlatform(IControllable(STRATEGY).platform()).multisig();
        factory = IFactory(IPlatform(IControllable(STRATEGY).platform()).factory());
        _upgradeFactory(); // upgrade to Factory v2.0.0
    }

    function testASFBugfix2() public {
        address[] memory assets = IStrategy(STRATEGY).assets();
        uint[] memory amounts = new uint[](2);
        amounts[0] = 100e18;
        amounts[1] = 10e6;

        deal(assets[0], address(this), amounts[0]);
        deal(assets[1], address(this), amounts[1]);
        IERC20(assets[0]).approve(vault, type(uint).max);
        IERC20(assets[1]).approve(vault, type(uint).max);
        vm.expectRevert();
        IVault(vault).depositAssets(assets, amounts, 0, address(this));

        // deploy new impl and upgrade
        address strategyImplementation = address(new ALMShadowFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.ALM_SHADOW_FARM, strategyImplementation);
        factory.upgradeStrategyProxy(STRATEGY);

        IVault(vault).depositAssets(assets, amounts, 0, address(this));
    }

    function _upgradeFactory() internal {
        // deploy new Factory implementation
        address newImpl = address(new Factory());

        // get the proxy address for the factory
        address factoryProxy = address(IPlatform(PLATFORM).factory());

        // prank as the platform because only it can upgrade
        vm.prank(PLATFORM);
        IProxy(factoryProxy).upgrade(newImpl);

        // refresh the factory instance to point to the proxy (now using new impl)
        factory = IFactory(factoryProxy);
    }
}
