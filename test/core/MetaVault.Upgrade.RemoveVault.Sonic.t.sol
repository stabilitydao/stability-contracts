// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console, Test, Vm} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626, IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MetaVault, IMetaVault, IStabilityVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";

/// @dev #336: add removeVault function to MetaVault, fix potential division on zero
contract MetaVaultSonicUpgradeRemoveVault is Test {
    uint public constant FORK_BLOCK = 35691649; // Jun-24-2025 12:57:07 PM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVault public metaVault;
    IMetaVaultFactory public metaVaultFactory;
    address public multisig;
    IPriceReader public priceReader;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSDC);
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());
        multisig = IPlatform(PLATFORM).multisig();

        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
    }

    function testRemoveSingleVault() public {
        _upgradeMetaVault(address(metaVault));

        uint snapshotId = vm.snapshotState();

        // todo

        vm.revertToState(snapshotId);
    }

    function testRemoveAllVaultsExceptLastOne() public {
        // todo
    }

    //region ------------------------------ Internal logic
    function _removeSubVault(uint vaultIndex) internal {
        address vault = metaVault.vaults()[vaultIndex];

        // ----------------------------- Set proportions to zero
        _setZeroProportions(vaultIndex, vaultIndex == 0 ? 1 : 0);

        // ----------------------------- Remove all from the volt so that only dust remains in it
        uint threshold = metaVault.USD_THRESHOLD();
        uint step;
        address[] memory assets = metaVault.assets();
        while (_getVaultOwnerAmountUsd(vault, address(metaVault) > threshold && step++ < 20)) {
            vm.prank(SonicConstantsLib.METAVAULT_metaUSD);
            metaVault.withdrawAssets(
                assets, metaVault.balanceOf(SonicConstantsLib.METAVAULT_metaUSD / 10), new uint[](1)
            );

            uint[] memory maxAmounts = new uint[](1);
            maxAmounts[0] = IERC20(assets[0]).balanceOf(address(metaVault));

            vm.prank(SonicConstantsLib.METAVAULT_metaUSD);
            metaVault.depositAssets(assets, maxAmounts, 0, SonicConstantsLib.METAVAULT_metaUSD);
        }

        // ----------------------------- Remove vault from MetaVault

        vm.expectRevert(); // multisig is required
        vm.prank(address(this));
        metaVault.removeVault(vault);

        vm.prank(multisig);
        metaVault.removeVault(vault);
    }

    function _getVaultOwnerAmountUsd(address vault, address owner) internal view returns (uint) {
        (uint vaultTvl,) = IStabilityVault(vault).tvl();
        uint vaultSharesBalance = IERC20(vault).balanceOf(owner);
        uint vaultTotalSupply = IERC20(vault).totalSupply();
        return
            vaultTotalSupply == 0 ? 0 : Math.mulDiv(vaultSharesBalance, vaultTvl, vaultTotalSupply, Math.Rounding.Floor);
    }

    function _setZeroProportions(uint fromIndex, uint toIndex) internal {
        IMetaVault metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSDC);
        multisig = IPlatform(PLATFORM).multisig();

        uint[] memory props = metaVault.targetProportions();
        props[toIndex] += props[fromIndex];
        props[fromIndex] = 0;

        vm.prank(multisig);
        metaVault.setTargetProportions(props);

        //        props = metaVault.targetProportions();
        //        uint[] memory current = metaVault.currentProportions();
        //        for (uint i; i < current.length; ++i) {
        //            console.log("i, current, target", i, current[i], props[i]);
        //        }
    }
    //endregion ------------------------------ Internal logic

    //region ------------------------------ Auxiliary Functions
    function _upgradeMetaVault(address metaVault_) internal {
        // Upgrade MetaVault to the new implementation
        address vaultImplementation = address(new MetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);
        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault_);
        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);
    }

    function _getAmountsForDeposit(
        uint usdValue,
        address[] memory assets
    ) internal view returns (uint[] memory depositAmounts) {
        depositAmounts = new uint[](assets.length);
        for (uint j; j < assets.length; ++j) {
            (uint price,) = priceReader.getPrice(assets[j]);
            require(price > 0, "UniversalTest: price is zero. Forget to add swapper routes?");
            depositAmounts[j] = usdValue * 10 ** IERC20Metadata(assets[j]).decimals() * 1e18 / price;
        }
    }

    function _dealAndApprove(
        address user,
        address metavault,
        address[] memory assets,
        uint[] memory amounts
    ) internal {
        for (uint j; j < assets.length; ++j) {
            deal(assets[j], user, amounts[j]);
            vm.prank(user);
            IERC20(assets[j]).approve(metavault, amounts[j]);
        }
    }
    //endregion ------------------------------ Auxiliary Functions
}
