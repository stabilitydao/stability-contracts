// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {Frontend} from "../../src/periphery/Frontend.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IVaultManager} from "../../src/interfaces/IVaultManager.sol";
import {IVault} from "../../src/interfaces/IVault.sol";

contract FrontendTestSonic is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    Frontend public immutable FRONTEND;
    address public multisig;

    uint internal constant FORK_BLOCK = 3451000; // Jan-11-2025 08:39:29 PM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        FRONTEND = new Frontend(PLATFORM);
        multisig = IPlatform(PLATFORM).multisig();
    }

    function testVaultsGasPage10() public view {
        FRONTEND.vaults(0, 10);
    }

    function testVaultsGasPage20() public view {
        FRONTEND.vaults(0, 20);
    }

    function testVaultsGasPage29() public view {
        FRONTEND.vaults(0, 29);
    }

    function testVaults() public {
        (uint total, address[] memory vaultAddress,,,,,, address[] memory strategy,,) = FRONTEND.vaults(0, 20);
        address[] memory allVaultAddresses = IVaultManager(IPlatform(PLATFORM).vaultManager()).vaultAddresses();

        assertEq(total, allVaultAddresses.length);
        assertEq(vaultAddress.length, 20);
        assertEq(vaultAddress[11], allVaultAddresses[11]);
        assertEq(strategy[11], address(IVault(allVaultAddresses[11]).strategy()));

        vm.expectRevert();
        FRONTEND.vaults(total, 20);

        (, vaultAddress,,,,,,,,) = FRONTEND.vaults(20, 20);
        assertEq(vaultAddress.length, total - 20);
    }

    function testGetBalanceAssetsGasPage10() public view {
        FRONTEND.getBalanceAssets(multisig, 0, 10);
    }

    function testGetBalanceAssetsGasPage20() public view {
        FRONTEND.getBalanceAssets(multisig, 0, 20);
    }

    function testGetBalanceAssets() public {
        (uint total, address[] memory asset, uint[] memory assetPrice,) = FRONTEND.getBalanceAssets(multisig, 0, 15);
        assertEq(asset.length, 15);
        assertGt(assetPrice[3], 0);

        (, asset,,) = FRONTEND.getBalanceAssets(multisig, 10, 15);
        assertEq(asset.length, total - 10);

        vm.expectRevert();
        FRONTEND.getBalanceAssets(multisig, total, 15);
    }

    function testGetBalanceVaultsGasPage10() public view {
        FRONTEND.getBalanceVaults(multisig, 0, 10);
    }

    function testGetBalanceVaultsGasPage20() public view {
        FRONTEND.getBalanceVaults(multisig, 0, 20);
    }

    function testGetBalanceVaults() public {
        (uint total, address[] memory vault, uint[] memory vaultSharePrice,) =
            FRONTEND.getBalanceVaults(multisig, 0, 20);
        address[] memory allVaultAddresses = IVaultManager(IPlatform(PLATFORM).vaultManager()).vaultAddresses();

        assertEq(total, allVaultAddresses.length);
        assertEq(vault.length, 20);
        assertGt(vaultSharePrice[11], 0);

        vm.expectRevert();
        FRONTEND.getBalanceVaults(multisig, total, 20);

        FRONTEND.getBalanceVaults(multisig, total - 1, 20000000000);
    }

    function testWhatToBuildAll() public view {
        FRONTEND.whatToBuild(0, 50);
    }

    function testWhatToBuild() public {
        (uint totalStrategies, string[] memory desc,,,,,,,,) = FRONTEND.whatToBuild(0, 1);
        assertEq(desc.length, 0);
        (, desc,,,,,,,,) = FRONTEND.whatToBuild(1, 2);
        assertEq(desc.length, 2);
        (, desc,,,,,,,,) = FRONTEND.whatToBuild(2, 10);
        assertEq(desc.length, 0);

        vm.expectRevert();
        FRONTEND.whatToBuild(totalStrategies, 10);
    }
}
