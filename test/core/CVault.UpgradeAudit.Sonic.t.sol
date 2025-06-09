// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../src/core/vaults/CVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {console, Test} from "forge-std/Test.sol";
import {SiloFarmStrategy} from "../../src/strategies/SiloFarmStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";

/// @dev CVault 1.7.3 upgrade test
contract CVaultUpgradeAuditSonicTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IVault public vault;
    IFactory public factory;
    address public multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 32834945)); // Jun-09-2025 06:26:27 AM +UTC
        vault = IVault(SonicConstantsLib.VAULT_C_USDC_S_49);
        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();
    }

    /// @notice Try to reproduce vulnerability #305
    function testCVaultReproduce305() public {
        address user1 = makeAddr("user1");
        address hacker = makeAddr("user2");
        IStrategy strategy = IStrategy(vault.strategy());
        address[] memory assets = vault.assets();
//        _upgradeCVault();
//        _upgradeStrategy(address(strategy));


        // ------------------------------ User 1 deposits amount
        deal(assets[0], user1, 1e6);
        deal(assets[0], hacker, 1e6);

        uint[] memory depositAmounts = new uint[](1);
        depositAmounts[0] = 1e6;

        vm.prank(user1);
        IERC20(assets[0]).approve(address(vault), type(uint).max);

        vm.prank(user1);
        vault.depositAssets(assets, depositAmounts, 0, user1);

        // ------------------------------ Set fuse mode
        vm.prank(multisig);
        strategy.emergencyStopInvesting();

        // ------------------------------ Add 1 wei directly on the strategy balance
        deal(strategy.underlying(), address(strategy), strategy.total() + 1);

        // ------------------------------ Hacker deposits amount
        vm.prank(hacker);
        IERC20(assets[0]).approve(address(vault), type(uint).max);

        vm.prank(hacker);
        vault.depositAssets(assets, depositAmounts, 0, hacker);

        // ------------------------------ Withdraw all
        uint balanceUser1 = vault.balanceOf(user1);
        uint balanceHacker = vault.balanceOf(hacker);
        assertGt(
            balanceHacker,
            balanceUser1 * 1000,
            "Hacker should have more than 1000x User1 balance"
        );

        // withdraw is not possible because fuse mode is disabled,
        // ERC4626StrategyBase tries to withdraw assets from underlying pool and doesn't try to use its balance
        // Result: nobody can withdraw assets from vault

//        vault.withdrawAssets(assets, vault.balanceOf(hacker1), new uint[](1));
//        vault.withdrawAssets(assets, vault.balanceOf(user1), new uint[](1));
    }

    /// @notice Ensure that hacker is not able to disable fuse mode
    function testCVaultUpgrade305() public {
        address user1 = makeAddr("user1");
        address hacker = makeAddr("user2");
        IStrategy strategy = IStrategy(vault.strategy());

        // ------------------------------ Provide assets to user1 and hacker
        address[] memory assets = vault.assets();
        deal(assets[0], user1, 1e6);
        deal(assets[0], hacker, 1e6);

        // ------------------------------ Upgrade both strategy and vault
        _upgradeCVault();
        _upgradeStrategy(address(strategy));

        // ------------------------------ User 1 deposits amount
        uint[] memory depositAmounts = new uint[](1);
        depositAmounts[0] = 1e6;

        vm.prank(user1);
        IERC20(assets[0]).approve(address(vault), type(uint).max);

        vm.prank(user1);
        vault.depositAssets(assets, depositAmounts, 0, user1);
        uint balanceUser1 = vault.balanceOf(user1);

        // ------------------------------ Set fuse mode
        vm.prank(multisig);
        strategy.emergencyStopInvesting();

        // ------------------------------ Hacker adds a lot of underlying directly on the strategy balance
        deal(strategy.underlying(), address(strategy), strategy.total() + 100e24);
        assertEq(strategy.fuseMode(), uint(IStrategy.FuseMode.FUSE_ON_1), "Fuse mode is still ON");

        // ------------------------------ Ensure that deposit is not available in fuse mode
        vm.prank(hacker);
        IERC20(assets[0]).approve(address(vault), type(uint).max);

        vm.expectRevert();
        vm.prank(hacker);
        vault.depositAssets(assets, depositAmounts, 0, hacker);

        // ------------------------------ Ensure that user 1 can withdraw
        assertEq(vault.balanceOf(user1), balanceUser1, "Balance of user 1 should not be changed");
        vm.prank(user1);
        vault.withdrawAssets(assets, balanceUser1, new uint[](1));

        assertApproxEqAbs(IERC20(assets[0]).balanceOf(user1), 1e6, 1e12, "User1 should have all assets back");
    }

    //region ---------------------- Auxiliary functions
    function _upgradeCVault() internal {
        // deploy new impl and upgrade
        address vaultImplementation = address(new CVault());
        vm.prank(multisig);
        factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: VaultTypeLib.COMPOUNDING,
                implementation: vaultImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: 1e10
            })
        );
        factory.upgradeVaultProxy(address(vault));
    }

    function _upgradeStrategy(address strategy) public {
        // deploy new impl and upgrade
        address strategyImplementation = address(new SiloStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: false,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategy);
    }

    //endregion ---------------------- Auxiliary functions
}
