// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console, Test} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MetaVault, IMetaVault, IStabilityVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";

contract MetaVaultSonicUpgrade1 is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IStabilityVault public metaVault;
    IMetaVaultFactory public metaVaultFactory;
    address public multisig;

    constructor() {
        // May-18-2025 03:55:11 PM +UTC
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 27775000));
        metaVault = IStabilityVault(SonicConstantsLib.METAVAULT_metaUSDC);
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());
        multisig = IPlatform(PLATFORM).multisig();
        _upgradeCVaults();
    }

    function testMetaVaultVaultUpgrade1() public {
        // console.logBytes4(bytes4(keccak256(bytes("WaitAFewBlocks()"))));
        IERC4626 wrapper = IERC4626(metaVaultFactory.wrapper(address(metaVault)));

        uint bal;
        address asset = wrapper.asset();
        deal(asset, address(this), 1e11);
        IERC20(asset).approve(address(wrapper), type(uint).max);
        wrapper.deposit(1000e6, address(this));
        bal = wrapper.balanceOf(address(this));
        vm.expectRevert(abi.encodeWithSelector(IStabilityVault.WaitAFewBlocks.selector));
        wrapper.redeem(bal / 3, address(this), address(this));

        // deploy new impl and upgrade
        address vaultImplementation = address(new MetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);
        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault);
        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);

        vm.prank(multisig);
        metaVault.setLastBlockDefenseDisabled(true);
        assertEq(metaVault.lastBlockDefenseDisabled(), true);

        wrapper.deposit(10e6, address(this));
        bal = wrapper.balanceOf(address(this));
        wrapper.redeem(bal / 3, address(this), address(this));

        vm.prank(multisig);
        metaVault.setLastBlockDefenseDisabled(false);
        assertEq(metaVault.lastBlockDefenseDisabled(), false);

        vm.roll(block.number + 6);
        wrapper.deposit(10e6, address(this));
        bal = wrapper.balanceOf(address(this));
        vm.expectRevert(abi.encodeWithSelector(IStabilityVault.WaitAFewBlocks.selector));
        wrapper.redeem(bal / 3, address(this), address(this));
    }

    function _upgradeCVaults() internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

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

        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_SiF);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_scUSD_ISF_scUSD);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_scUSD_ISF_USDC);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_8);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_27);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_34);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_36);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_49);

        vm.startPrank(multisig);
        IStabilityVault(SonicConstantsLib.VAULT_C_USDC_SiF).setLastBlockDefenseDisabled(true);
        IStabilityVault(SonicConstantsLib.VAULT_C_USDC_S_8).setLastBlockDefenseDisabled(true);
        IStabilityVault(SonicConstantsLib.VAULT_C_USDC_S_27).setLastBlockDefenseDisabled(true);
        IStabilityVault(SonicConstantsLib.VAULT_C_USDC_S_34).setLastBlockDefenseDisabled(true);
        IStabilityVault(SonicConstantsLib.VAULT_C_USDC_S_36).setLastBlockDefenseDisabled(true);
        IStabilityVault(SonicConstantsLib.VAULT_C_USDC_S_49).setLastBlockDefenseDisabled(true);
        vm.stopPrank();
    }
}
