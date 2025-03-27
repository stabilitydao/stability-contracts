// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console, Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {SiloLeverageStrategy} from "../../src/strategies/SiloLeverageStrategy.sol";

contract SiLUpgradeTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STRATEGY = 0xfF9C35acDA4b136F71B1736B2BDFB5479f111C4A;
    address public vault;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(16296000); // Mar-27-2025 08:48:46 AM +UTC
        vault = IStrategy(STRATEGY).vault();
    }

    function testSiLUpgrade() public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address multisig = IPlatform(PLATFORM).multisig();

        // deploy new impl and upgrade
        address strategyImplementation = address(new SiloLeverageStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO_LEVERAGE,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: false,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(STRATEGY);

        //uint balanceWas = IERC20(vault).balanceOf(multisig);
        vm.prank(vault);
        IStrategy(STRATEGY).doHardWork();
        //console.log('got', IERC20(vault).balanceOf(multisig) - balanceWas);
    }
}
