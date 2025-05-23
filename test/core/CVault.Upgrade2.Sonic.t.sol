// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console, Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";

/// @dev CVault 1.7.0 upgrade test
contract CVaultUpgrade2SonicTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IStabilityVault public vault;
    IFactory public factory;
    address public multisig;

    constructor() {
        // May-18-2025 03:55:11 PM +UTC
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 27775000));
        vault = IStabilityVault(SonicConstantsLib.VAULT_C_USDC_SiF);
        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();
    }

    function testCVaultUpgrade2() public {
        uint bal;
        address[] memory assets = vault.assets();
        deal(assets[0], address(this), 1e9);
        IERC20(assets[0]).approve(address(vault), type(uint).max);
        uint[] memory depositAmounts = new uint[](1);
        depositAmounts[0] = 10e6;
        vault.depositAssets(assets, depositAmounts, 0, address(this));
        bal = vault.balanceOf(address(this));
        vm.expectRevert(abi.encodeWithSelector(IStabilityVault.WaitAFewBlocks.selector));
        vault.withdrawAssets(assets, bal, new uint[](1));

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

        vm.prank(multisig);
        vault.setLastBlockDefenseDisabled(true);
        assertEq(vault.lastBlockDefenseDisabled(), true);

        vault.depositAssets(assets, depositAmounts, 0, address(this));
        bal = vault.balanceOf(address(this));
        vault.withdrawAssets(assets, bal, new uint[](1));

        vm.prank(multisig);
        vault.setLastBlockDefenseDisabled(false);

        vault.depositAssets(assets, depositAmounts, 0, address(this));
        bal = vault.balanceOf(address(this));
        vm.expectRevert(abi.encodeWithSelector(IStabilityVault.WaitAFewBlocks.selector));
        vault.withdrawAssets(assets, bal, new uint[](1));
    }
}
