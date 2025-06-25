// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";
import {AaveStrategy} from "../../src/strategies/AaveStrategy.sol";
import {EulerStrategy} from "../../src/strategies/EulerStrategy.sol";
import {SiloFarmStrategy} from "../../src/strategies/SiloFarmStrategy.sol";
import {SiloManagedFarmStrategy} from "../../src/strategies/SiloManagedFarmStrategy.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626, IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MetaVault, IMetaVault, IStabilityVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {console, Test, Vm} from "forge-std/Test.sol";

/// @dev #336: add removeVault function to MetaVault, fix potential division on zero
contract MetaVaultSonicUpgradeRemoveVault is Test {
    // uint public constant FORK_BLOCK = 35691649; // Jun-24-2025 12:57:07 PM +UTC
    uint public constant FORK_BLOCK = 35804605; // Jun-25-2025 06:29:05 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVault public metaVault;
    IMetaVaultFactory public metaVaultFactory;
    address public multisig;
    IPriceReader public priceReader;

    struct VaultState {
        address[] vaults;
        uint[] metaVaultTokensToWithdraw;
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
        _upgradeVaults(SonicConstantsLib.METAVAULT_metaUSDC, SonicConstantsLib.WRAPPED_METAVAULT_metaUSDC, true);
    }

    function testRemoveSingleVaultStatic() public {
        uint countVaults = metaVault.vaults().length;
        for (uint i; i < countVaults; ++i) {
            uint snapshotId = vm.snapshotState();
            _testRemoveSingleVault(i);
            vm.revertToState(snapshotId);
        }
    }

    function testRemoveSeveralVaultsStatic() public {
        // use testRemoveSeveralVaults__Fuzzy to test this function with random values, it takes long time
        uint countVaults = metaVault.vaults().length;
        for (uint i; i < countVaults; ++i) {
            uint snapshotId = vm.snapshotState();
            _testRemoveSeveralVaults(i, 1 + i / 2);
            vm.revertToState(snapshotId);
        }
    }

    //    function testRemoveSeveralVaults__Fuzzy(uint startVaultIndex, uint countVaultsToRemove) public {
    //        startVaultIndex = bound(startVaultIndex, 0, metaVault.vaults().length - 1);
    //        countVaultsToRemove = bound(countVaultsToRemove, 0, metaVault.vaults().length - 3);
    //        _testRemoveSeveralVaults(startVaultIndex, countVaultsToRemove);
    //    }

    //region ------------------------------ Internal logic
    function _testRemoveSingleVault(uint indexVaultToRemove) internal {
        if (_prepareToRemoveSubVault(indexVaultToRemove)) {
            VaultState memory stateBefore = _getVaultState();
            _removeSubVault(metaVault.vaults()[indexVaultToRemove]);
            VaultState memory stateAfter = _getVaultState();

            _checkVaultStateAfterRemove(stateBefore, stateAfter, 1, indexVaultToRemove);

            // ------------------------------ Try to make actions after remove
            _makeWithdrawDeposit();
            // no reverts
        }
    }

    function _testRemoveSeveralVaults(uint startVaultIndex, uint countVaultsToRemove) internal {
        uint countRemovedVaults;
        for (uint i; i < countVaultsToRemove; ++i) {
            // _displayVaultsInfo();
            uint indexVaultToRemove = (startVaultIndex + i) % metaVault.vaults().length;
            if (_prepareToRemoveSubVault(indexVaultToRemove)) {
                VaultState memory stateBefore = _getVaultState();
                // _displayVaultsInfo();
                _removeSubVault(metaVault.vaults()[indexVaultToRemove]);
                VaultState memory stateAfter = _getVaultState();

                ++countRemovedVaults;
                _checkVaultStateAfterRemove(stateBefore, stateAfter, 1, indexVaultToRemove);
            }
        }

        // ------------------------------ Try to make actions after remove
        _makeWithdrawDeposit();
        // no reverts
    }

    function _getVaultState() internal view returns (VaultState memory state) {
        state.vaults = metaVault.vaults();
        state.totalSupply = metaVault.totalSupply();
        (state.tvl,) = metaVault.tvl();
        state.targetProportions = metaVault.targetProportions();
        state.currentProportions = metaVault.currentProportions();
        (state.price,) = metaVault.price();
        state.balanceMetaUsdVault = metaVault.balanceOf(SonicConstantsLib.METAVAULT_metaUSD);
        state.metaVaultTokensToWithdraw = new uint[](state.vaults.length);
        for (uint i; i < state.vaults.length; ++i) {
            address vault = state.vaults[i];
            state.metaVaultTokensToWithdraw[i] = _getVaultOwnerAmountUsd(vault, address(metaVault));
        }
        return state;
    }

    function _checkVaultStateAfterRemove(
        VaultState memory stateBefore,
        VaultState memory stateAfter,
        uint countRemovedVaults,
        uint indexRemovedVault
    ) internal pure {
        assertEq(
            stateAfter.vaults.length, stateBefore.vaults.length - countRemovedVaults, "Vault count should decrease"
        );
        assertEq(
            stateAfter.targetProportions.length,
            stateBefore.targetProportions.length - countRemovedVaults,
            "Target proportions length is reduced"
        );
        assertEq(
            stateAfter.currentProportions.length,
            stateBefore.currentProportions.length - countRemovedVaults,
            "Current proportions length is reduced"
        );

        assertGe(stateBefore.totalSupply, stateAfter.totalSupply, "Total supply should not increase");
        if (stateBefore.metaVaultTokensToWithdraw[indexRemovedVault] > 10_000) {
            assertLt(
                _getDiffPercent18(
                    stateBefore.totalSupply - stateAfter.totalSupply,
                    stateBefore.metaVaultTokensToWithdraw[indexRemovedVault]
                ),
                uint(1e14), // 0.01%
                "Total can be decreased only by the amount of removed vault shares"
            );
        } else {
            assertLt(
                _getDiffPercent18(stateBefore.totalSupply, stateAfter.totalSupply),
                uint(1e10), // 0.000001%
                "Total can be changes only a bit"
            );
        }

        assertGe(stateBefore.tvl, stateAfter.tvl, "TVL should not increase");

        assertLt(
            _getDiffPercent18(stateAfter.tvl, stateBefore.tvl),
            uint(1e10), // 0.000001%
            "TVL should not changed"
        );

        assertApproxEqAbs(stateAfter.price, stateBefore.price, 1, "Price should not changed");

        assertLt(
            _getDiffPercent18(stateAfter.balanceMetaUsdVault, stateBefore.balanceMetaUsdVault),
            uint(1e10), // 0.000001%
            "Balance of MetaUSD vault should not changed"
        );

        for (uint i; i < stateAfter.vaults.length; ++i) {
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
                "Target proportions should not changed at all"
            );
            assertLt(
                _getDiffPercent18(stateAfter.currentProportions[i], stateBefore.currentProportions[index]),
                uint(1e10), // 0.000001%
                "Current proportions should not changed a lot"
            );
            assertLt(
                _getDiffPercent18(stateAfter.metaVaultTokensToWithdraw[i], stateBefore.metaVaultTokensToWithdraw[index]),
                uint(1e10), // 0.000001%
                "Balance of metaVault-tokens should not changed"
            );
        }
    }

    function _displayVaultsInfo() internal view {
        address[] memory vaults = metaVault.vaults();
        console.log("i, vault, max withdraw, total supply");
        for (uint i; i < vaults.length; ++i) {
            address vault = vaults[i];
            IStrategy strategy = IVault(vault).strategy();
            uint totalSupply = IStabilityVault(vault).totalSupply();
            uint[] memory amounts = strategy.maxWithdrawAssets();
            (, uint[] memory assetAmounts) = strategy.assetsAmounts();
            uint maxWithdraw = Math.min(totalSupply, totalSupply * amounts[0] / assetAmounts[0]);
            console.log(i, vault, maxWithdraw, totalSupply);
        }
        console.log("maxWithdrawAmountTx", metaVault.maxWithdrawAmountTx());
    }

    function _prepareToRemoveSubVault(uint vaultIndex) internal returns (bool vaultWithFullLiquidityRemoved) {
        address vault = metaVault.vaults()[vaultIndex];

        {
            IStrategy strategy = IVault(vault).strategy();
            uint totalSupply = IStabilityVault(vault).totalSupply();
            uint[] memory amounts = strategy.maxWithdrawAssets();
            (, uint[] memory assetAmounts) = strategy.assetsAmounts();
            uint maxWithdraw = Math.min(totalSupply, totalSupply * amounts[0] / assetAmounts[0]);
            if (10_000 * (totalSupply - maxWithdraw) / totalSupply != 0) {
                // we are NOT able to withdraw all assets from the vault
                // so we can't remove it
                return false;
            }
        }

        // ----------------------------- Set proportions of the target vault to zero
        _setZeroProportions(vaultIndex, vaultIndex == 0 ? 1 : 0);

        // ----------------------------- Withdraw all from the volt (leave only dust)
        uint threshold = metaVault.USD_THRESHOLD();
        uint step;

        do {
            _makeWithdrawDeposit();
            ++step;

            uint amount = _getVaultOwnerAmountUsd(vault, address(metaVault));
            if (amount < threshold) break;
        } while (step < 10);

        assertLt(
            _getVaultOwnerAmountUsd(vault, address(metaVault)),
            threshold,
            "Vault shouldn't have more than threshold amount"
        );

        return true;
    }

    function _removeSubVault(address vault) internal {
        // console.log("_removeSubVault", vault);
        vm.expectRevert(); // only multisig is able to remove vault
        vm.prank(address(this));
        metaVault.removeVault(vault);

        vm.prank(multisig);
        metaVault.removeVault(vault);
    }

    function _makeWithdrawDeposit() internal {
        address[] memory assets = metaVault.assetsForWithdraw();

        uint amountToWithdraw = metaVault.balanceOf(SonicConstantsLib.METAVAULT_metaUSD) / 2;

        vm.prank(SonicConstantsLib.METAVAULT_metaUSD);
        metaVault.withdrawAssets(assets, amountToWithdraw, new uint[](1));
        vm.roll(block.number + 6);

        uint[] memory maxAmounts = new uint[](1);
        maxAmounts[0] = IERC20(assets[0]).balanceOf(address(SonicConstantsLib.METAVAULT_metaUSD));

        vm.prank(SonicConstantsLib.METAVAULT_metaUSD);
        IERC20(assets[0]).approve(address(metaVault), maxAmounts[0]);

        vm.prank(SonicConstantsLib.METAVAULT_metaUSD);
        metaVault.depositAssets(assets, maxAmounts, 0, SonicConstantsLib.METAVAULT_metaUSD);
        vm.roll(block.number + 6);
    }

    function _getVaultOwnerAmountUsd(address vault, address owner) internal view returns (uint) {
        (uint vaultTvl,) = IStabilityVault(vault).tvl();
        uint vaultSharesBalance = IERC20(vault).balanceOf(owner);
        uint vaultTotalSupply = IERC20(vault).totalSupply();
        return
            vaultTotalSupply == 0 ? 0 : Math.mulDiv(vaultSharesBalance, vaultTvl, vaultTotalSupply, Math.Rounding.Floor);
    }

    function _setMaxProportions(uint toIndex) internal {
        multisig = IPlatform(PLATFORM).multisig();

        uint[] memory props = metaVault.targetProportions();

        uint fromIndex = props[0];
        for (uint i; i < props.length; ++i) {
            if (props[i] > props[fromIndex]) {
                fromIndex = i;
                break;
            }
        }
        props[toIndex] += props[fromIndex];
        props[fromIndex] = 0;

        vm.prank(multisig);
        metaVault.setTargetProportions(props);
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

    function _getDiffPercent18(uint x, uint y) internal pure returns (uint) {
        if (x == 0) return 0;
        return x > y ? (x - y) * 1e18 / x : (y - x) * 1e18 / x;
    }

    //endregion ------------------------------ Auxiliary Functions

    //region ------------------------------ Upgrade Vaults
    function _upgradeVaults(address metaVault_, address wrapped_, bool upgradeStrategies_) internal {
        multisig = IPlatform(PLATFORM).multisig();
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());

        address newMetaVaultImplementation = address(new MetaVault());
        address newWrapperImplementation = address(new WrappedMetaVault());
        vm.startPrank(multisig);

        metaVaultFactory.setMetaVaultImplementation(newMetaVaultImplementation);
        metaVaultFactory.setWrappedMetaVaultImplementation(newWrapperImplementation);

        address[] memory proxies = new address[](2);
        proxies[0] = metaVault_;
        proxies[1] = wrapped_;
        metaVaultFactory.upgradeMetaProxies(proxies);
        vm.stopPrank();

        _upgradeCVaultsWithStrategies(IMetaVault(metaVault_), upgradeStrategies_);
    }

    function _upgradeCVaultsWithStrategies(IMetaVault metaVault_, bool upgradeStrategies_) internal {
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

        if (upgradeStrategies_) {
            address[] memory vaults = metaVault_.vaults();

            for (uint i; i < vaults.length; i++) {
                factory.upgradeVaultProxy(vaults[i]);
                if (CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.AAVE)) {
                    _upgradeAaveStrategy(address(IVault(payable(vaults[i])).strategy()));
                } else if (CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.SILO)) {
                    _upgradeSiloStrategy(address(IVault(payable(vaults[i])).strategy()));
                } else if (CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.EULER)) {
                    _upgradeEulerStrategy(address(IVault(payable(vaults[i])).strategy()));
                } else if (
                    CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.SILO_FARM)
                ) {
                    _upgradeSiloFarmStrategy(address(IVault(payable(vaults[i])).strategy()));
                } else if (
                    CommonLib.eq(
                        IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.SILO_MANAGED_FARM
                    )
                ) {
                    _upgradeSiloManagedFarmStrategy(address(IVault(payable(vaults[i])).strategy()));
                } else {
                    revert("Unknown strategy for CVault");
                }
            }
        }
    }

    function _upgradeAaveStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new AaveStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.AAVE,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeEulerStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new EulerStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.EULER,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeSiloStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new SiloStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeSiloFarmStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new SiloFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO_FARM,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeSiloManagedFarmStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new SiloManagedFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO_MANAGED_FARM,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }
    //endregion ------------------------------ Upgrade Vaults
}
