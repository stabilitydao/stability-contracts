// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CVault} from "../../src/core/vaults/CVault.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ISilo} from "../../src/integrations/silo/ISilo.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IMetaVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {console, Test} from "forge-std/Test.sol";
import {SiloManagedFarmStrategy} from "../../src/strategies/SiloManagedFarmStrategy.sol";

contract SiMFUpgradeTest is Test {
    uint public constant FORK_BLOCK = 33508152; // Jun-12-2025 05:49:24 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public constant METAVAULT = SonicConstantsLib.METAVAULT_metaUSDC;
    address public constant VAULT_C = SonicConstantsLib.VAULT_C_USDC_SiMF_Valmore;
    IMetaVault public metaVault;
    IMetaVaultFactory public metaVaultFactory;
    address public multisig;
    IPriceReader public priceReader;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        metaVault = IMetaVault(METAVAULT);
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());
        multisig = IPlatform(PLATFORM).multisig();

        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
    }

    /// @notice #326: Add maxWithdrawAssets and poolTvl to IStrategy
    function testMetaVaultUpdate326() public {
        IVault vault = IVault(VAULT_C);
        IStrategy strategy = vault.strategy();
        address[] memory assets = vault.assets();

        // ------------------- upgrade strategy
        // _upgradeCVault(SonicConstantsLib.VAULT_C);
        _upgradeManagedSiloFarmStrategy(address(strategy));

        // ------------------- get max amount ot vault tokens that can be withdrawn
        uint maxWithdraw = vault.balanceOf(METAVAULT);

        // ------------------- our balance and max available liquidity in AAVE token
        SiloManagedFarmStrategy sifStrategy = SiloManagedFarmStrategy(address(strategy));
        IFactory.Farm memory farm = IFactory(IPlatform(PLATFORM).factory()).farm(sifStrategy.farmId());
        ISilo silo = ISilo(farm.addresses[0]);

        // ------------------- borrow almost all cash
        uint balanceAssets = silo.convertToAssets(silo.balanceOf(address(strategy)));
        uint availableLiquidity = strategy.maxWithdrawAssets(0)[0];
        uint maxWithdraw4626 = silo.maxWithdraw(address(strategy));

        assertEq(availableLiquidity, maxWithdraw4626, "strategy.maxWithdrawAssets uses IE4626.maxWithdraw");

        // ------------------- amount of vault tokens that can be withdrawn
        uint balanceToWithdraw =
            availableLiquidity == balanceAssets ? maxWithdraw : availableLiquidity * maxWithdraw / balanceAssets - 1;

        // ------------------- ensure that we cannot withdraw amount on 1% more than the calculated balance
        if (availableLiquidity < balanceAssets * 99 / 100) {
            //            console.log("availableLiquidity", availableLiquidity);
            //            console.log("balanceAssets", balanceAssets);
            vm.expectRevert();
            vm.prank(METAVAULT);
            vault.withdrawAssets(assets, maxWithdraw, new uint[](1));
        }

        // ------------------- ensure that we can withdraw calculated amount of vault tokens
        vm.prank(METAVAULT);
        vault.withdrawAssets(assets, balanceToWithdraw, new uint[](1));

        // ------------------- check poolTvl
        (uint price,) = priceReader.getPrice(assets[0]);

        assertEq(silo.totalAssets() * price / (10 ** IERC20Metadata(assets[0]).decimals()), strategy.poolTvl());
    }

    //region ------------------------------ Auxiliary Functions
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

    function _upgradeCVault(address vault) internal {
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

        factory.upgradeVaultProxy(vault);
    }

    function _upgradeManagedSiloFarmStrategy(address strategyAddress) internal {
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
    //endregion ------------------------------ Auxiliary Functions
}
