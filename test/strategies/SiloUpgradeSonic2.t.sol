// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console, Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {SiloAdvancedLeverageStrategy} from "../../src/strategies/SiloAdvancedLeverageStrategy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";

contract SiloUpgradeSonic2Test is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STRATEGY = 0xDf077C7ffFa6B140d76dE75c792F49D6cB62AE19;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(13624880); // Mar-14-2025 07:49:27 AM +UTC
    }

    function testSiloUpgrade2() public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address multisig = IPlatform(PLATFORM).multisig();

        // Deploy new implementation and upgrade
        address strategyImplementation = address(new SiloAdvancedLeverageStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO_ADVANCED_LEVERAGE,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(STRATEGY);

        // Try to deposit in a vault that wasn't working before
        address vault = IStrategy(STRATEGY).vault();
        console.log("Vault address:", vault);

        address[] memory assets = IStrategy(STRATEGY).assets();
        console.log("Number of assets:", assets.length);
        for (uint i = 0; i < assets.length; i++) {
            console.log("Asset", i, ":", assets[i]);
        }

        uint[] memory amounts = new uint[](assets.length);
        amounts[0] = 1e18; // 1 token

        // Fund the test contract
        deal(assets[0], address(this), amounts[0]);

        // Approve vault to spend tokens
        for (uint i = 0; i < assets.length; i++) {
            IERC20(assets[i]).approve(vault, amounts[i]);
        }

        // Try to deposit
        IVault(vault).depositAssets(assets, amounts, 0, address(this));
    }
}
