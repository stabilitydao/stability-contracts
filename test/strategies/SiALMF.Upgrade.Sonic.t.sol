// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PriceReader} from "../../src/core/PriceReader.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {SiloALMFStrategy} from "../../src/strategies/SiloALMFStrategy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {Test} from "forge-std/Test.sol";
import {Factory} from "../../src/core/Factory.sol";
import {IProxy} from "../../src/interfaces/IProxy.sol";

contract SiALMFUpgradeTest is Test {
    // uint public constant FORK_BLOCK = 39484599; // Jul-21-2025 08:14:43 AM +UTC
    uint public constant FORK_BLOCK = 40550698; // Jul-28-2025 05:46:21 AM +UTC

    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    address internal multisig;
    IFactory internal factory;
    IStabilityVault internal vault;
    IStrategy internal strategy;
    IPriceReader internal priceReader;

    struct State {
        uint ltv;
        uint maxLtv;
        uint leverage;
        uint maxLeverage;
        uint targetLeverage;
        uint targetLeveragePercent;
        uint collateralAmount;
        uint debtAmount;
        uint total;
        uint sharePrice;
        uint balanceAsset;
        uint realTvl;
        uint vaultBalance;
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();
        vault = IStabilityVault(SonicConstantsLib.VAULT_C_WMETAUSD_USDC_121);
        strategy = IVault(address(vault)).strategy();
        priceReader = IPriceReader(
            IPlatform(IControllable(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).platform()).priceReader()
        );

        _upgradePlatform(address(priceReader));
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        _upgradeWrappedMetaVault();
        _upgradeFactory(); // upgrade to Factory v2.0.0
        _upgradeCVault();

        _upgradeStrategy();
        _upgradeCVault(SonicConstantsLib.VAULT_C_WMETAUSD_USDC_121);
    }

    function testSingleDepositWithdraw() public {
        _removeUnusedVaults();

        // ---------------------------------- Set whitelist for transient cache
        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(address(strategy), true);

        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(SonicConstantsLib.METAVAULT_METAUSD, true);

        // ---------------------------------- Deposit
        uint amount = 17e18;
        _getMetaTokensOnBalance(address(this), amount, true, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);

        IERC20(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).approve(address(vault), amount);

        address[] memory assets = vault.assets();
        uint[] memory amountsMax = new uint[](1);
        amountsMax[0] = amount;

        uint gas0 = gasleft();
        vault.depositAssets(assets, amountsMax, 0, address(this));
        vm.roll(block.number + 6);
        //console.log("!!!!!!!!!!!!!!! gas used for deposit", gas0 - gasleft());
        //assertLt(gas0 - gasleft(), 12e6, "Deposit should not use more than 12 mln gas");

        // ---------------------------------- Withdraw
        uint shares = vault.balanceOf(address(this));
        gas0 = gasleft();
        uint[] memory withdrawn = vault.withdrawAssets(assets, shares, new uint[](1));
        //console.log("!!!!!!!!!!!!!!! gas used for withdraw", gas0 - gasleft());
        assertLt(gas0 - gasleft(), 16e6, "Withdraw should not use more than 16 mln gas");

        assertApproxEqAbs(amount, withdrawn[0], amount / 100 * 2, "Withdrawn amount does not match deposited amount");
        assertEq(vault.balanceOf(address(this)), 0, "Shares should be zero after withdrawal");

        // ---------------------------------- Hardwork
        {
            gas0 = gasleft();
            address hardWorker = IPlatform(PLATFORM).hardWorker();

            vm.prank(hardWorker);
            IVault(address(vault)).doHardWork();

            //console.log("!!!!!!!!!!!!!!!!!!! gas used for hardwork", gas0 - gasleft());
            assertLt(gas0 - gasleft(), 16e6, "Hardwork should not use more than 16 mln gas");
        }

        // ---------------------------------- Emergency exit
        {
            gas0 = gasleft();

            vm.prank(multisig);
            strategy.emergencyStopInvesting();

            // console.log("!!!!!!!!!!!!!!!!!!!! gas used for emergency exit", gas0 - gasleft());
            assertLt(gas0 - gasleft(), 16e6, "Emergency exit should not use more than 16 mln gas");
        }
    }

    function testMultipleDepositWithdraw() public {
        _testMultipleDepositWithdraw(100e18);
    }

    //    function testMultipleDepositWithdraw_Fuzzy(uint baseAmount) public {
    //        baseAmount = bound(baseAmount, 10e18, 1000e18);
    //        _testMultipleDepositWithdraw(baseAmount);
    //    }

    function _testMultipleDepositWithdraw(uint baseAmount) internal {
        _removeUnusedVaults();

        // ---------------------------------- Set whitelist for transient cache
        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(address(strategy), true);

        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(SonicConstantsLib.METAVAULT_METAUSD, true);

        // ---------------------------------- Deposit and withdraw
        address[] memory assets = vault.assets();

        State memory state = _getState();
        //console.log("before ltv, leverage, shareprice", state.ltv, state.leverage, state.sharePrice);
        //console.log("max ltv, target leverage", state.maxLtv, state.targetLeverage);

        uint totalDeposited;
        uint totalWithdrawn;
        for (uint i; i < 20; ++i) {
            {
                uint amount = i % 5 == 0 ? baseAmount * 11 : i % 3 == 0 ? baseAmount / 7 : baseAmount;

                _getMetaTokensOnBalance(address(this), amount, true, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);
                IERC20(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).approve(address(vault), amount);

                uint[] memory amountsMax = new uint[](1);
                amountsMax[0] = amount;

                vault.depositAssets(assets, amountsMax, 0, address(this));
                vm.roll(block.number + 6);

                totalDeposited += amount;
            }
            state = _getState();
            assertLt(state.ltv, state.maxLtv, "LTV should be less than max LTV after deposit");
            //console.log("after deposit ltv, leverage, shareprice", state.ltv, state.leverage, state.sharePrice);

            {
                uint balance = vault.balanceOf(address(this));
                uint shares = i % 5 == 0 ? balance * 99 / 100 : i % 2 == 0 ? balance / 7 : balance / 100;
                totalWithdrawn += vault.withdrawAssets(assets, shares, new uint[](1))[0];
                vm.roll(block.number + 6);
            }
            state = _getState();
            //console.log("after withdraw ltv, leverage, shareprice", state.ltv, state.leverage, state.sharePrice);
            assertLt(state.ltv, state.maxLtv, "LTV should be less than max LTV after withdrawal");
        }

        {
            uint shares = vault.balanceOf(address(this));
            if (shares != 0) {
                totalWithdrawn += vault.withdrawAssets(assets, shares, new uint[](1))[0];
            }
        }

        assertApproxEqAbs(
            totalDeposited, totalWithdrawn, totalDeposited / 100 * 2, "Withdrawn amount does not match deposited amount"
        );
        assertEq(vault.balanceOf(address(this)), 0, "Shares should be zero after withdrawal");

        vm.warp(block.timestamp + 7200);
        deal(SonicConstantsLib.TOKEN_WS, IPlatform(PLATFORM).hardWorker(), 10e18); // emulate Merkl rewards

        address hardWorker = IPlatform(PLATFORM).hardWorker();
        vm.prank(hardWorker);
        IVault(address(vault)).doHardWork();
    }

    //region ------------------------------------ Helpers
    function _upgradeStrategy() internal {
        address strategyImplementation = address(new SiloALMFStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO_ALMF_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(address(strategy));
    }

    function _upgradeCVault(address vault_) internal {
        // deploy new impl and upgrade
        address vaultImplementation = address(new CVault());
        vm.prank(multisig);
        factory.setVaultImplementation(VaultTypeLib.COMPOUNDING, vaultImplementation);

        factory.upgradeVaultProxy(vault_);
    }

    function _upgradePlatform(address priceReader_) internal {
        // we need to skip 1 day to update the swapper
        // but we cannot simply skip 1 day, because the silo oracle will start to revert with InvalidPrice
        // vm.warp(block.timestamp - 86400);
        rewind(86400);

        IPlatform platform = IPlatform(IControllable(priceReader_).platform());

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = address(priceReader_);
        // proxies[1] = platform.ammAdapter(keccak256(bytes(AmmAdapterIdLib.META_VAULT))).proxy;
        //proxies[2] = platform.swapper();

        implementations[0] = address(new PriceReader());
        // implementations[1] = address(new MetaVaultAdapter());
        //implementations[2] = address(new Swapper());

        // vm.startPrank(multisig);
        // platform.cancelUpgrade();

        vm.startPrank(multisig);
        platform.announcePlatformUpgrade("2025.08.0-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }

    function _upgradeMetaVault(address metaVault_) internal {
        IMetaVaultFactory metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());
        // Upgrade MetaVault to the new implementation
        address vaultImplementation = address(new MetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);
        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault_);
        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);
    }

    function _upgradeWrappedMetaVault() internal {
        IMetaVaultFactory metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());

        address newWrapperImplementation = address(new WrappedMetaVault());
        vm.startPrank(multisig);
        metaVaultFactory.setWrappedMetaVaultImplementation(newWrapperImplementation);
        address[] memory proxies = new address[](2);
        proxies[0] = SonicConstantsLib.WRAPPED_METAVAULT_METAS;
        proxies[1] = SonicConstantsLib.WRAPPED_METAVAULT_METAUSD;
        metaVaultFactory.upgradeMetaProxies(proxies);
        vm.stopPrank();
    }

    function _upgradeCVault() internal {
        // deploy new impl and upgrade
        address vaultImplementation = address(new CVault());
        vm.prank(multisig);
        factory.setVaultImplementation(VaultTypeLib.COMPOUNDING, vaultImplementation);
        factory.upgradeVaultProxy(address(vault));
    }

    function _dealAndApprove(address user, address metavault, address[] memory assets, uint[] memory amounts) internal {
        for (uint j; j < assets.length; ++j) {
            deal(assets[j], user, amounts[j]);
            vm.prank(user);
            IERC20(assets[j]).approve(metavault, amounts[j]);
        }
    }

    function _getMetaTokensOnBalance(
        address user,
        uint amountMetaVaultTokens,
        bool wrap,
        address wrappedMetaVault_
    ) internal {
        IMetaVault metaVault = IMetaVault(IWrappedMetaVault(wrappedMetaVault_).metaVault());
        address asset = address(metaVault) == SonicConstantsLib.METAVAULT_METAUSD
            ? SonicConstantsLib.TOKEN_USDC
            : SonicConstantsLib.TOKEN_WS;

        // we don't know exact amount of USDC required to receive exact amountMetaVaultTokens
        // so we deposit a bit large amount of USDC
        address[] memory _assets = metaVault.assetsForDeposit();
        uint[] memory amountsMax = new uint[](1);
        amountsMax[0] = address(metaVault) == SonicConstantsLib.METAVAULT_METAUSD
            ? 2 * amountMetaVaultTokens / 1e12
            : 2 * amountMetaVaultTokens;

        deal(asset, user, amountsMax[0]);

        vm.startPrank(user);
        IERC20(asset).approve(address(metaVault), IERC20(asset).balanceOf(user));
        metaVault.depositAssets(_assets, amountsMax, 0, user);
        vm.roll(block.number + 6);
        vm.stopPrank();

        if (wrap) {
            vm.startPrank(user);
            IWrappedMetaVault wrappedMetaVault = IWrappedMetaVault(wrappedMetaVault_);
            metaVault.approve(address(wrappedMetaVault), metaVault.balanceOf(user));
            wrappedMetaVault.deposit(metaVault.balanceOf(user), user, 0);
            vm.stopPrank();

            vm.roll(block.number + 6);
        }
    }

    function _getState() internal view returns (State memory state) {
        ILeverageLendingStrategy _strategy = ILeverageLendingStrategy(address(strategy));

        (state.sharePrice,) = _strategy.realSharePrice();

        (
            state.ltv,
            state.maxLtv,
            state.leverage,
            state.collateralAmount,
            state.debtAmount,
            state.targetLeveragePercent
        ) = _strategy.health();

        state.total = strategy.total();
        state.maxLeverage = 100_00 * 1e18 / (1e18 - state.maxLtv);
        state.targetLeverage = state.maxLeverage * state.targetLeveragePercent / 100_00;
        state.balanceAsset = IERC20(IStrategy(address(_strategy)).assets()[0]).balanceOf(address(_strategy));
        (state.realTvl,) = _strategy.realTvl();
        state.vaultBalance = IVault(IStrategy(address(_strategy)).vault()).balanceOf(address(this));

        // console.log("targetLeverage, leverage, total", state.targetLeverage, state.leverage, state.total);

        //        console.log("ltv", state.ltv);
        //        console.log("maxLtv", state.maxLtv);
        //        console.log("targetLeverage", state.targetLeverage);
        //        console.log("leverage", state.leverage);
        //        console.log("total", state.total);
        //        console.log("collateralAmount", state.collateralAmount);
        //        console.log("debtAmount", state.debtAmount);
        //        console.log("targetLeveragePercent", state.targetLeveragePercent);
        //        console.log("maxLeverage", state.maxLeverage);
        //        console.log("realTvl", state.realTvl);
        return state;
    }

    function _removeUnusedVaults() internal {
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METASCUSD);

        // todo UsdAmountLessThreshold(6074204700030295904090)
        //        vm.prank(multisig);
        //        IMetaVault(SonicConstantsLib.METAVAULT_METAUSD).removeVault(SonicConstantsLib.METAVAULT_METASCUSD);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).removeVault(SonicConstantsLib.VAULT_C_USDC_SIF);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).removeVault(SonicConstantsLib.VAULT_C_USDC_S_8);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).removeVault(SonicConstantsLib.VAULT_C_USDC_S_27);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).removeVault(SonicConstantsLib.VAULT_C_USDC_S_34);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).removeVault(SonicConstantsLib.VAULT_C_USDC_S_36);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC)
            .removeVault(SonicConstantsLib.VAULT_C_USDC_STABILITY_STABLEJACK);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).removeVault(SonicConstantsLib.VAULT_C_USDC_S_112);

        // _removeUnusedVaultsMetaScUsd();
    }

    function _removeUnusedVaultsMetaScUsd() internal {
        // there are 5 sub vaults in metascUSD
        // two of them have target proportions 0.1%
        // let's try to remove them completely

        // --------------------------------- Set target proportions to 0
        _setProportions(SonicConstantsLib.METAVAULT_METASCUSD, 0, 2, 2e16);
        _setProportions(SonicConstantsLib.METAVAULT_METASCUSD, 1, 2, 2e16);

        // --------------------------------- Withdraw liquidity from the sub vaults
        _tryToWithdraw(
            IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD), SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD, 10_00
        );
        _tryToWithdraw(
            IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD), SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD, 10_00
        );
        _tryToWithdraw(
            IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD), SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD, 10_00
        );
        _tryToWithdraw(
            IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD), SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD, 10_00
        );

        _setProportions(SonicConstantsLib.METAVAULT_METASCUSD, 0, 2, 0);
        _setProportions(SonicConstantsLib.METAVAULT_METASCUSD, 1, 2, 0);

        // --------------------------------- Remove sub vaults
        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD).removeVault(SonicConstantsLib.VAULT_C_SCUSD_S_46); // index 0

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD).removeVault(SonicConstantsLib.VAULT_C_SCUSD_EULER_RE7LABS); // index 1
    }

    function _tryToWithdraw(IMetaVault multiVault, address user, uint percents) internal {
        uint balance = multiVault.balanceOf(user);
        address[] memory assets = multiVault.assetsForWithdraw();

        //        console.log("balance", balance);
        //        console.log("subvalut", multiVault.vaultForWithdraw());

        vm.prank(user);
        multiVault.withdrawAssets(assets, balance * percents / 100_00, new uint[](1));

        vm.roll(block.number + 6);
    }

    function _setProportions(address metaVault_, uint fromIndex, uint toIndex, uint min) internal {
        IMetaVault metaVault = IMetaVault(metaVault_);
        multisig = IPlatform(PLATFORM).multisig();

        uint[] memory props = metaVault.targetProportions();
        props[toIndex] = props[toIndex] + props[fromIndex] - min;
        props[fromIndex] = min;

        vm.prank(multisig);
        metaVault.setTargetProportions(props);

        //        props = metaVault.targetProportions();
        //        uint[] memory current = metaVault.currentProportions();
        //        for (uint i; i < current.length; ++i) {
        //            console.log("i, current, target", i, current[i], props[i]);
        //        }
    }

    function _upgradeFactory() internal {
        // deploy new Factory implementation
        address newImpl = address(new Factory());

        // get the proxy address for the factory
        address factoryProxy = address(IPlatform(PLATFORM).factory());

        // prank as the platform because only it can upgrade
        vm.prank(PLATFORM);
        IProxy(factoryProxy).upgrade(newImpl);

        // refresh the factory instance to point to the proxy (now using new impl)
        factory = IFactory(factoryProxy);
    }
    //endregion ------------------------------------ Helpers
}
