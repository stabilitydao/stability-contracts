// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {IVaultManager} from "../../src/interfaces/IVaultManager.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import "../../src/strategies/TridentPearlFarmStrategy.sol";
import {IHardWorker} from "../../src/interfaces/IHardWorker.sol";
import {RealLib} from "../../chains/RealLib.sol";

contract TPFUpgradeTest is Test {
    address public constant PLATFORM = 0xB7838d447deece2a9A5794De0f342B47d0c1B9DC;
    address public constant STRATEGY = 0xF85530577DCB8A00C2254a1C7885F847230C3097;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("REAL_RPC_URL")));
        vm.rollFork(1126880); // Nov 15 2024 09:17:19 AM
    }

    function testTPFUpgrade() public {
        IVaultManager vaultManager = IVaultManager(IPlatform(PLATFORM).vaultManager());
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        // IHardWorker hw = IHardWorker(IPlatform(PLATFORM).hardWorker());
        // ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());
        address multisig = IPlatform(PLATFORM).multisig();

        vm.expectRevert();
        vaultManager.vaults();

        // deploy new impl and upgrade
        address strategyImplementation = address(new TridentPearlFarmStrategy());
        vm.prank(multisig);
        IPlatform(PLATFORM).addOperator(multisig);
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.TRIDENT_PEARL_FARM,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );
        factory.upgradeStrategyProxy(STRATEGY);

        vaultManager.vaults();
    }
}
