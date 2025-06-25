// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console, Test, Vm} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC4626, IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MetaVault, IMetaVault, IStabilityVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
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

    struct VaultState {
        address[] vaults;
        uint totalSupply;
        uint tvl;
        uint price;
        uint balanceMetaUsdVault;
        uint[] targetProportions;
        uint[] currentProportions;
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSDC);
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());
        multisig = IPlatform(PLATFORM).multisig();

        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
    }

    function testRemoveSingleVault0() public {
        _testRemoveSingleVault(8);
    }

    function testRemoveSingleVault__Fuzzy(uint indexVaultToRemove) public {
        indexVaultToRemove = bound(indexVaultToRemove, 0, metaVault.vaults().length - 1);
        _testRemoveSingleVault(indexVaultToRemove);
    }

    function testRemoveSeveralVaults__Fuzzy(uint startVaultIndex, uint countVaultsToRemove) public {
        startVaultIndex = bound(startVaultIndex, 0, metaVault.vaults().length - 1);
        countVaultsToRemove = bound(countVaultsToRemove, 0, metaVault.vaults().length - 2);
        _testRemoveSeveralVaults(startVaultIndex, countVaultsToRemove);
    }

    //region ------------------------------ Internal logic
    function _testRemoveSingleVault(uint indexVaultToRemove) internal {
        _upgradeMetaVault(address(metaVault));

        VaultState memory stateBefore = _getVaultState();
        _removeSubVault(indexVaultToRemove);

        // ------------------------------ Check vault state after remove
        VaultState memory stateAfter = _getVaultState();
        _checkVaultStateAfterRemove(stateBefore, stateAfter);

        // ------------------------------ Try to make actions after remove
        _makeWithdrawDeposit();

        VaultState memory stateFinal = _getVaultState();
        _checkVaultStateAfterRemove(stateBefore, stateFinal);
    }

    function _testRemoveSeveralVaults(uint startVaultIndex, uint countVaultsToRemove) internal {
        _upgradeMetaVault(address(metaVault));

        VaultState memory stateBefore = _getVaultState();

        for (uint i; i < countVaultsToRemove; ++i) {
            _removeSubVault(startVaultIndex < metaVault.vaults().length ? startVaultIndex : 0);

            // ------------------------------ Check vault state after remove
            VaultState memory stateAfter = _getVaultState();
            _checkVaultStateAfterRemove(stateBefore, stateAfter);
        }

        // ------------------------------ Try to make actions after remove
        _makeWithdrawDeposit();

        VaultState memory stateFinal = _getVaultState();
        _checkVaultStateAfterRemove(stateBefore, stateFinal);
    }

    function _getVaultState() internal view returns (VaultState memory state) {
        state.vaults = metaVault.vaults();
        state.totalSupply = metaVault.totalSupply();
        (state.tvl, ) = metaVault.tvl();
        state.targetProportions = metaVault.targetProportions();
        state.currentProportions = metaVault.currentProportions();
        (state.price, ) = metaVault.price();
        state.balanceMetaUsdVault = metaVault.balanceOf(SonicConstantsLib.METAVAULT_metaUSD);
        return state;
    }

    function _checkVaultStateAfterRemove(VaultState memory stateBefore, VaultState memory stateAfter) internal pure {
        console.log("_checkVaultStateAfterRemove.1");
        assertEq(stateAfter.vaults.length, stateBefore.vaults.length - 1, "Vault count should decrease by one");
        assertEq(
            stateAfter.targetProportions.length,
            stateBefore.targetProportions.length - 1,
            "Target proportions length is reduced by one"
        );
        assertEq(
            stateAfter.currentProportions.length,
            stateBefore.currentProportions.length - 1,
            "Current proportions length is reduced by one"
        );
        console.log("_checkVaultStateAfterRemove.2");

        assertApproxEqAbs(stateAfter.totalSupply, stateBefore.totalSupply, 1, "Total supply should not changed");
        console.log("_checkVaultStateAfterRemove.3");
        assertApproxEqAbs(stateAfter.tvl, stateBefore.tvl, 1, "TVL should not changed");
        console.log("_checkVaultStateAfterRemove.4");
        assertApproxEqAbs(stateAfter.price, stateBefore.price, 1, "Price should not changed");
        console.log("_checkVaultStateAfterRemove.5");
        assertApproxEqAbs(
            stateAfter.balanceMetaUsdVault,
            stateBefore.balanceMetaUsdVault,
            1,
            "Balance of MetaUSD vault should not changed"
        );
        console.log("_checkVaultStateAfterRemove.6");

        for (uint i; i < stateAfter.vaults.length; ++i) {
            console.log("_checkVaultStateAfterRemove.7", i);
            // find index of the vault in the stateBefore
            uint index = type(uint).max;

            for (uint j; j < stateBefore.vaults.length; ++j) {
                if (stateAfter.vaults[i] == stateBefore.vaults[j]) {
                    index = j;
                    break;
                }
            }
            require(index != type(uint).max, "Vault not found");

            assertEq(
                stateAfter.targetProportions[i],
                stateBefore.targetProportions[index],
                "Target proportions should not changed"
            );
            assertEq(
                stateAfter.currentProportions[i],
                stateBefore.currentProportions[index],
                "Current proportions should not changed"
            );
        }
    }

    function _removeSubVault(uint vaultIndex) internal {
        address vault = metaVault.vaults()[vaultIndex];

        // ----------------------------- Set proportions of the target vault to zero
        _setZeroProportions(vaultIndex, vaultIndex == 0 ? 1 : 0);

        // ----------------------------- Remove all actives from the volt so that only dust remains in it
        uint threshold = metaVault.USD_THRESHOLD();
        uint step;

        do {
            _makeWithdrawDeposit();
            ++step;

            uint amount = _getVaultOwnerAmountUsd(vault, address(metaVault));
            if (amount < threshold) break;
        } while (step < 20);

        assertLt(
            _getVaultOwnerAmountUsd(vault, address(metaVault)),
            threshold,
            "Vault shouldn't have more than threshold amount"
        );

        // ----------------------------- Remove vault from MetaVault

        vm.expectRevert(); // only multisig is able to remove vault
        vm.prank(address(this));
        metaVault.removeVault(vault);

        vm.prank(multisig);
        metaVault.removeVault(vault);
    }

    function _makeWithdrawDeposit() internal {
        console.log("_makeWithdrawDeposit.1");
        address[] memory assets = metaVault.assets();

        console.log("_makeWithdrawDeposit", metaVault.balanceOf(SonicConstantsLib.METAVAULT_metaUSD));

        uint amountToWithdraw = metaVault.balanceOf(SonicConstantsLib.METAVAULT_metaUSD) / 100;

        vm.prank(SonicConstantsLib.METAVAULT_metaUSD);
        metaVault.withdrawAssets(assets, amountToWithdraw, new uint[](1));
        vm.roll(block.number + 6);

        console.log("_makeWithdrawDeposit.2");
        uint[] memory maxAmounts = new uint[](1);
        maxAmounts[0] = IERC20(assets[0]).balanceOf(address(metaVault));

        vm.prank(SonicConstantsLib.METAVAULT_metaUSD);
        IERC20(assets[0]).approve(address(metaVault), maxAmounts[0]);

        vm.prank(SonicConstantsLib.METAVAULT_metaUSD);
        metaVault.depositAssets(assets, maxAmounts, 0, SonicConstantsLib.METAVAULT_metaUSD);
        console.log("_makeWithdrawDeposit.3", metaVault.balanceOf(SonicConstantsLib.METAVAULT_metaUSD));
    }

    function _getVaultOwnerAmountUsd(address vault, address owner) internal view returns (uint) {
        (uint vaultTvl,) = IStabilityVault(vault).tvl();
        uint vaultSharesBalance = IERC20(vault).balanceOf(owner);
        uint vaultTotalSupply = IERC20(vault).totalSupply();
        return
            vaultTotalSupply == 0 ? 0 : Math.mulDiv(vaultSharesBalance, vaultTvl, vaultTotalSupply, Math.Rounding.Floor);
    }

    function _setZeroProportions(uint fromIndex, uint toIndex) internal {
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
