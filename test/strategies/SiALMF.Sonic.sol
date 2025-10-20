// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ISilo} from "../../src/integrations/silo/ISilo.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {UniversalTest} from "../base/UniversalTest.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";
import {console} from "forge-std/console.sol";

contract SiloALMFStrategyTest is SonicSetup, UniversalTest {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    uint public constant FARM_META_USD_USDC_53 = 53;
    uint public constant FARM_META_USD_SCUSD_54 = 54;
    uint public constant FARM_METAS_S_55 = 55;

    uint public constant REVERT_NO = 0;
    uint public constant REVERT_NOT_ENOUGH_LIQUIDITY = 1;
    uint public constant REVERT_INSUFFICIENT_BALANCE = 2;

    address internal _currentMetaVault;

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

    uint internal constant FORK_BLOCK = 37477020; // Jul-07-2025 12:24:42 PM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        // vm.rollFork(34471950); // Jun-17-2025 09:08:37 AM +UTC
        // vm.rollFork(36717785); // Jul-01-2025 01:21:29 PM +UTC
        // vm.rollFork(37477020); // Jul-07-2025 12:24:42 PM +UTC
        // vm.rollFork(38132683); // Jul-12-2025 01:38:42 AM +UTC

        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;

        _upgradePlatform(IPlatform(PLATFORM).multisig(), IPlatform(PLATFORM).priceReader());
    }

    function testSiALMFSonic() public universalTest {
        //        _addStrategy(FARM_META_USD_SCUSD_54);
        _addStrategy(FARM_METAS_S_55);
        _addStrategy(FARM_META_USD_USDC_53);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_ALMF_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }

    function _preDeposit() internal override {
        address multisig = platform.multisig();

        //        _showPrices(
        //            IPlatform(PLATFORM).priceReader(),
        //            IPlatform(IControllable(currentStrategy).platform()).priceReader()
        //        );
        uint farmId = _currentFarmId();
        if (farmId == FARM_META_USD_USDC_53 || farmId == FARM_META_USD_SCUSD_54) {
            _currentMetaVault = SonicConstantsLib.METAVAULT_METAUSD;
        } else if (farmId == FARM_METAS_S_55) {
            _currentMetaVault = SonicConstantsLib.METAVAULT_METAS;
        } else {
            revert("Unknown farmId");
        }

        IPlatform platform = IPlatform(PLATFORM); // IControllable(currentStrategy).platform());
        _upgradeMetaVault(address(platform), _currentMetaVault);
        upgradeWrappedMetaVault();

        vm.prank(multisig);
        IMetaVault(_currentMetaVault).changeWhitelist(currentStrategy, true);

        // ---------------------------------- Set whitelist for transient cache
        {
            IPriceReader priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
            console.log("price reader 1", IPlatform(PLATFORM).priceReader());
            console.log("price reader 2", IPlatform(IControllable(currentStrategy).platform()).priceReader());
            IPriceReader priceReader2 = IPriceReader(IPlatform(IControllable(currentStrategy).platform()).priceReader());

            _changeWhitelistTransientCache(multisig, priceReader);
            _changeWhitelistTransientCache(multisig, priceReader2);
        }

        // ---------------------------------- Make additional tests
        uint snapshot = vm.snapshotState();
        if (farmId == FARM_META_USD_USDC_53) {
            _testStrategyParams_All();
            _checkMaxDepositAssets_All();
        } else if (farmId == FARM_META_USD_SCUSD_54) {
            // farm FARM_META_USD_SCUSD_54 uses Balancer V3 vault
            // we cannot put unlimited flash loan on its balance - we get arithmetic underflow inside sendTo
            _checkMaxDepositAssets_MaxDeposit_LimitedFlash();
            _checkMaxDepositAssets_AmountMoreThanMaxDeposit_LimitedFlash();
        } else {
            _testStrategyParams_All();
            _checkMaxDepositAssets_All();
        }
        vm.revertToState(snapshot);

        // ---------------------------------- Set up flash loan
        _setUpFlashLoanVault(getUnlimitedFlashAmount(), ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2);
    }

    function _preHardWork() internal override {
        // emulate merkl rewards
        deal(SonicConstantsLib.TOKEN_WS, currentStrategy, 1e18);
        deal(SonicConstantsLib.TOKEN_SILO, currentStrategy, 1e18);
    }

    //region --------------------------------------- Strategy params tests
    //    function _showPrices(address priceReader1, address priceReader2) internal {
    //        console.log("!!!!!!!!!!!!!!!!!!Price reader 1, get price wS");
    //        (uint price1, ) = IPriceReader(priceReader1).getPrice(SonicConstantsLib.TOKEN_WS);
    //        console.log("!!!!!!!!!!!!!!!!!!Price reader 2, get price metas");
    //        (uint price2, ) = IPriceReader(priceReader2).getPrice(SonicConstantsLib.METAVAULT_METAS);
    //        console.log("!!!!!!!!!!!!!!!!!!Price reader 2, get price wS");
    //        (uint price3, ) = IPriceReader(priceReader2).getPrice(SonicConstantsLib.TOKEN_WS);
    //        console.log("reader1, reader2", priceReader1, priceReader2);
    //        console.log("price1, price2, price3", price1, price2, price3);
    //
    //        (uint priceUsdc, ) = IPriceReader(priceReader2).getPrice(SonicConstantsLib.TOKEN_USDC);
    //        console.log("priceUsdc", priceUsdc);
    //    }

    function _testStrategyParams_All() internal {
        uint snapshot = vm.snapshotState();

        // --------------------------------------------- Ensure that rebalance doesn't change real share price
        _testRebalance(75_00, 85_00, true); // rebalance with free flash loan

        // --------------------------------------------- targetLeveragePercent - percent of max leverage.
        _testDepositWithdraw(80_00, 1000, true);
        _testOneDepositTwoWithdraw(80_00, 1000, true);
        _testOneDepositTwoWithdraw(85_00, 10_000, false);
        _testOneDepositTwoWithdraw(75_00, 50_000, false);

        // --------------------------------------------- try to set HIGH values of deposit/withdraw-params
        _setDepositParams(100_00, 99_80);
        _setWithdrawParams(100_00, 110_00, 110_00);
        _testMultipleDepositsAndMultipleWithdraw(80_00, 1000, true); // free flash loan

        _setWithdrawParams(110_00, 100_00, 100_00);
        _testMultipleDepositsAndMultipleWithdraw(80_00, 1000, true); // free flash loan

        _setDepositParams(110_00, 98_00);
        _setWithdrawParams(100_00, 100_00, 100_00);
        _testMultipleDepositsAndMultipleWithdraw(80_00, 1000, true); // free flash loan

        vm.revertToState(snapshot);
    }

    /// @notice Deposit, check state, withdraw all, check state
    function _testDepositWithdraw(uint targetLeveragePercent_, uint amountNoDecimals, bool freeFlashLoan_) internal {
        uint snapshot = vm.snapshotState();

        if (freeFlashLoan_) {
            _setUpFlashLoanVault(0, ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1);
        } else {
            _setUpFlashLoanVault(getUnlimitedFlashAmount(), ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2);
        }

        _setTargetLeveragePercent(targetLeveragePercent_);
        IStrategy strategy = IStrategy(currentStrategy);

        // --------------------------------------------- Deposit
        uint[] memory amountsToDeposit = new uint[](1);
        amountsToDeposit[0] = amountNoDecimals * 10 ** IERC20Metadata(strategy.assets()[0]).decimals();

        // emulate rewards BEFORE deposit
        deal(SonicConstantsLib.TOKEN_WS, currentStrategy, 177e18);

        State memory state0 = _getState();
        (uint depositedAssets, uint depositedValue) = _tryToDeposit(strategy, amountsToDeposit, REVERT_NO);
        vm.roll(block.number + 6);
        State memory state1 = _getState();

        uint withdrawn1 = _tryToWithdraw(strategy, depositedValue);
        vm.roll(block.number + 6);
        State memory state2 = _getState();

        uint wsFinalBalance = IERC20(SonicConstantsLib.TOKEN_WS).balanceOf(currentStrategy);
        vm.revertToState(snapshot);

        // --------------------------------------------- Check results
        assertEq(depositedAssets, amountsToDeposit[0], "Deposited amount should be equal to amountsToDeposit");
        if (freeFlashLoan_) {
            assertApproxEqAbs(
                depositedAssets,
                withdrawn1,
                depositedAssets / 100,
                "Withdrawn amount should be equal to deposited amount 1"
            );

            // some amount left in the collateral vault after full withdraw
            assertApproxEqAbs(
                depositedAssets,
                withdrawn1 + state2.collateralAmount,
                depositedAssets / 100_000,
                "Withdrawn amount should be equal to deposited amount 2"
            );
        }

        assertLt(state0.total, state1.total, "Total should increase after deposit");
        assertEq(state1.total, state0.total + depositedValue, "Total should increase on expected value after deposit 2");
        assertEq(state2.total, state0.total, "Total should decrease after first withdraw");

        assertEq(wsFinalBalance, 177e18, "wS balance should not change after deposit and withdraw");
    }

    function _testRebalance(uint targetLeveragePercent_, uint targetLeveragePercentNew_, bool freeFlashLoan_) internal {
        uint snapshot = vm.snapshotState();

        if (freeFlashLoan_) {
            _setUpFlashLoanVault(0, ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1);
        } else {
            _setUpFlashLoanVault(getUnlimitedFlashAmount(), ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2);
        }

        _setTargetLeveragePercent(targetLeveragePercent_);
        IStrategy strategy = IStrategy(currentStrategy);

        // emulate rewards BEFORE deposit
        deal(SonicConstantsLib.TOKEN_WS, currentStrategy, 177e18);

        // --------------------------------------------- Deposit max amount (but less maxDeposit to be able to rebalance)
        uint[] memory amountsToDeposit = strategy.maxDepositAssets();
        amountsToDeposit[0] = amountsToDeposit[0] / 4;

        State[4] memory states;
        states[0] = _getState();
        (uint depositedAssets, uint depositedValue) =
            _tryToDepositToVault(strategy.vault(), amountsToDeposit, REVERT_NO);
        vm.roll(block.number + 6);
        states[1] = _getState();
        // console.log("deposit", amountsToDeposit[0], depositedAssets, depositedValue);

        // --------------------------------------------- Rebalance: ensure that real share price is not changed
        (uint sharePrice,) = ILeverageLendingStrategy(address(strategy)).realSharePrice();
        (uint realTvl,) = ILeverageLendingStrategy(address(strategy)).realTvl();
        // console.log("start rebalance", sharePrice, realTvl, strategy.total());
        ILeverageLendingStrategy(address(strategy))
            .rebalanceDebt(targetLeveragePercentNew_, sharePrice * (1e6 - 1) / 1e6);
        // 0

        (uint sharePriceAfter,) = ILeverageLendingStrategy(address(strategy)).realSharePrice();
        (uint realTvlAfter,) = ILeverageLendingStrategy(address(strategy)).realTvl();
        states[2] = _getState();

        uint withdrawn1 = _tryToWithdrawFromVault(strategy.vault(), depositedValue);
        vm.roll(block.number + 6);
        states[3] = _getState();

        uint wsFinalBalance = IERC20(SonicConstantsLib.TOKEN_WS).balanceOf(currentStrategy);
        vm.revertToState(snapshot);

        // --------------------------------------------- Check results
        assertApproxEqAbs(sharePriceAfter, sharePrice, 1e10, "Share price should not change after rebalance");
        assertApproxEqAbs(realTvl, realTvlAfter, 1e14, "TVL should not change after rebalance");

        assertEq(depositedAssets, amountsToDeposit[0], "Deposited amount should be equal to amountsToDeposit");
        if (freeFlashLoan_) {
            assertApproxEqAbs(
                depositedAssets,
                withdrawn1,
                depositedAssets / 100,
                "Withdrawn amount should be equal to deposited amount 1"
            );

            // some amount left in the collateral vault after full withdraw
            assertApproxEqAbs(
                depositedAssets,
                withdrawn1 + states[3].collateralAmount,
                depositedAssets / 100_000,
                "Withdrawn amount should be equal to deposited amount 2"
            );
        }

        assertLt(states[0].vaultBalance, states[1].vaultBalance, "vaultBalance should increase after deposit");
        assertEq(
            states[1].vaultBalance,
            states[0].vaultBalance + depositedValue,
            "vaultBalance should increase on expected value after deposit 3"
        );
        assertEq(states[2].vaultBalance, states[1].vaultBalance, "vaultBalance should not change after rebalance");
        assertEq(states[3].vaultBalance, states[0].vaultBalance, "vaultBalance should decrease after withdraw");

        assertNotEq(sharePrice, 0, "Share price is not 0");

        assertEq(
            wsFinalBalance,
            177e18,
            "wS balance should not change after on rebalance (only hardwork can process rewards)"
        );
        //        console.log("sharePrice.before", sharePrice);
        //        console.log("sharePrice.after", sharePriceAfter);
        //        console.log("realTvl.before", realTvl);
        //        console.log("realTvl.after", realTvlAfter);
    }

    /// @notice Deposit, check state, withdraw half, check state, withdraw all, check state
    function _testOneDepositTwoWithdraw(
        uint targetLeveragePercent_,
        uint amountNoDecimals,
        bool freeFlashLoan_
    ) internal {
        uint snapshot = vm.snapshotState();

        if (freeFlashLoan_) {
            _setUpFlashLoanVault(0, ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1);
        } else {
            _setUpFlashLoanVault(getUnlimitedFlashAmount(), ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2);
        }

        _setTargetLeveragePercent(targetLeveragePercent_);
        IStrategy strategy = IStrategy(currentStrategy);

        // --------------------------------------------- Make initial deposit to the strategy
        uint[] memory amountsToDeposit = new uint[](1);
        amountsToDeposit[0] = 1000 * 10 ** IERC20Metadata(strategy.assets()[0]).decimals();
        _tryToDeposit(strategy, amountsToDeposit, REVERT_NO);
        vm.roll(block.number + 6);

        // --------------------------------------------- Deposit
        amountsToDeposit = new uint[](1);
        amountsToDeposit[0] = amountNoDecimals * 10 ** IERC20Metadata(strategy.assets()[0]).decimals();

        State memory state0 = _getState();
        (uint depositedAssets, uint depositedValue) = _tryToDeposit(strategy, amountsToDeposit, REVERT_NO);
        vm.roll(block.number + 6);
        State memory state1 = _getState();

        uint withdrawn1 = _tryToWithdraw(strategy, depositedValue / 2);
        vm.roll(block.number + 6);
        State memory state2 = _getState();

        uint withdrawn2 = _tryToWithdraw(strategy, depositedValue - depositedValue / 2);
        vm.roll(block.number + 6);
        State memory state3 = _getState();

        vm.revertToState(snapshot);

        // --------------------------------------------- Check results
        assertEq(depositedAssets, amountsToDeposit[0], "Deposited amount should be equal to amountsToDeposit");
        if (freeFlashLoan_) {
            assertApproxEqAbs(
                depositedAssets,
                withdrawn1 + withdrawn2,
                depositedAssets / 100,
                "Withdrawn amount should be equal to deposited amount 3"
            );
        }

        // todo
        //        assertApproxEqAbs(state0.targetLeverage, state1.leverage,
        //            2000,
        //            "The leverage should be equal to target leverage after deposit"
        //        );
        //        assertApproxEqAbs(state0.targetLeverage, state2.leverage,
        //            2000,
        //            "The leverage should be equal to target leverage after withdrawing half"
        //        );
        //        assertApproxEqAbs(state0.targetLeverage, state3.leverage,
        //            2000,
        //            "The leverage should be equal to target leverage after withdrawing all"
        //        );

        assertLt(state0.total, state1.total, "Total should increase after deposit");
        assertEq(state1.total, state0.total + depositedValue, "Total should increase on expected value after deposit 1");
        assertEq(
            state2.total,
            state0.total + depositedValue - depositedValue / 2,
            "Total should decrease after first withdraw"
        );
        assertEq(state3.total, state0.total, "Total should return to initial value after second withdraw");
    }

    function _testMultipleDepositsAndMultipleWithdraw(
        uint targetLeveragePercent_,
        uint amountNoDecimals,
        bool freeFlashLoan_
    ) internal {
        uint snapshot = vm.snapshotState();

        if (freeFlashLoan_) {
            _setUpFlashLoanVault(0, ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1);
        } else {
            _setUpFlashLoanVault(getUnlimitedFlashAmount(), ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2);
        }

        _setTargetLeveragePercent(targetLeveragePercent_);
        IStrategy strategy = IStrategy(currentStrategy);

        // --------------------------------------------- Make initial deposit to the strategy
        uint[] memory amountsToDeposit = new uint[](1);
        amountsToDeposit[0] = (freeFlashLoan_ ? 100 : 10_000) * 10 ** IERC20Metadata(strategy.assets()[0]).decimals();
        _tryToDeposit(strategy, amountsToDeposit, REVERT_NO);
        vm.roll(block.number + 6);

        uint valueBefore = strategy.total();

        uint totalDeposited = amountsToDeposit[0];
        uint totalWithdrawn = 0;

        // --------------------------------------------- Deposit
        for (uint i; i < 10; ++i) {
            amountsToDeposit = new uint[](1);
            amountsToDeposit[0] = amountNoDecimals * 10 ** IERC20Metadata(strategy.assets()[0]).decimals();

            // State memory state0 = _getState();
            (uint depositedAssets, uint depositedValue) = _tryToDeposit(strategy, amountsToDeposit, REVERT_NO);
            vm.roll(block.number + 6);
            totalDeposited += depositedAssets;
            // console.log("i, deposited assets, value", i, depositedAssets, depositedValue);
            // State memory state1 = _getState();

            uint withdrawn1 = _tryToWithdraw(strategy, depositedValue * (i + 1) / (i + 2));
            vm.roll(block.number + 6);
            // State memory state2 = _getState();
            totalWithdrawn += withdrawn1;
        }

        uint withdrawn2 = _tryToWithdraw(strategy, (strategy.total() - valueBefore) / 2);
        vm.roll(block.number + 6);
        // State memory state3 = _getState();
        totalWithdrawn += withdrawn2;

        withdrawn2 = _tryToWithdraw(strategy, strategy.total());
        vm.roll(block.number + 6);
        // state3 = _getState();
        totalWithdrawn += withdrawn2;

        vm.revertToState(snapshot);

        assertApproxEqAbs(
            totalDeposited,
            totalWithdrawn,
            totalDeposited / 1000,
            "Withdrawn amount should be close to deposited amount 4"
        );
        //        assertLe(
        //            _getDiffPercent18(totalDeposited, totalWithdrawn),
        //            1e18 / 100 / 100, // less 0.01%
        //            "Withdrawn amount should be close to deposited amount"
        //        );
    }

    //endregion --------------------------------------- Strategy params tests

    //region --------------------------------------- maxDeposit tests
    /// @notice Ensure that the value returned by SiloALMFStrategy.maxDepositAssets is not unlimited.
    /// Ensure that we can deposit max amount and that we CAN'T deposit more than max amount.
    function _checkMaxDepositAssets_All() internal {
        _checkMaxDepositAssets_MaxDeposit_UnlimitedFlash();
        _checkMaxDepositAssets_AmountMoreThanMaxDeposit_UnlimitedFlash();
        _checkMaxDepositAssets_MaxDeposit_LimitedFlash();
        _checkMaxDepositAssets_AmountMoreThanMaxDeposit_LimitedFlash();
    }

    function _checkMaxDepositAssets_MaxDeposit_UnlimitedFlash() internal {
        IStrategy strategy = IStrategy(currentStrategy);

        // ---------------------------- try to deposit maxDeposit - unlimited flash loan is available
        uint snapshot = vm.snapshotState();
        _setUpFlashLoanVault(getUnlimitedFlashAmount(), ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2);
        uint[] memory maxDepositAssets = strategy.maxDepositAssets();
        (uint deposited,) = _tryToDeposit(strategy, maxDepositAssets, REVERT_NO);

        // ---------------------------- try to withdraw full amount back without any losses
        uint withdrawn = _tryToWithdrawAll(strategy);
        vm.revertToState(snapshot);

        assertLt(
            _getDiffPercent18(deposited, withdrawn),
            1e18 * 97 / 100,
            "Withdrawn amount should be close to deposited amount (fee amount)"
        );
    }

    function _checkMaxDepositAssets_AmountMoreThanMaxDeposit_UnlimitedFlash() internal {
        IStrategy strategy = IStrategy(currentStrategy);

        // ---------------------------- try to deposit maxDeposit + 1% - unlimited flash loan is available
        uint snapshot = vm.snapshotState();
        _setUpFlashLoanVault(getUnlimitedFlashAmount(), ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3);
        uint[] memory maxDepositAssets = strategy.maxDepositAssets();
        for (uint i = 0; i < maxDepositAssets.length; i++) {
            maxDepositAssets[i] = maxDepositAssets[i] * 101 / 100;
        }
        _tryToDeposit(strategy, maxDepositAssets, REVERT_NOT_ENOUGH_LIQUIDITY);
        vm.revertToState(snapshot);
    }

    function _checkMaxDepositAssets_MaxDeposit_LimitedFlash() internal {
        IStrategy strategy = IStrategy(currentStrategy);

        // ---------------------------- try to deposit maxDeposit with limited flash loan
        uint snapshot = vm.snapshotState();
        _setUpFlashLoanVault(0, ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2);
        uint[] memory maxDepositAssets = strategy.maxDepositAssets();

        _tryToDeposit(strategy, maxDepositAssets, REVERT_NO);

        //        // ---------------------------- try to withdraw full amount back without any losses
        //        uint withdrawn = _tryToWithdrawAll(strategy);
        vm.revertToState(snapshot);
        //
        //        assertLt(_getDiffPercent18(deposited, withdrawn), 1e18*97/100, "Withdrawn amount should be close to deposited amount (fee amount)");
    }

    function _checkMaxDepositAssets_AmountMoreThanMaxDeposit_LimitedFlash() internal {
        IStrategy strategy = IStrategy(currentStrategy);

        // ---------------------------- try to deposit maxDeposit + 1% with limited flash loan
        uint snapshot = vm.snapshotState();
        address flashLoanVault = _setUpFlashLoanVault(0, ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2);

        uint farmId = _currentFarmId();
        address borrowVault = farmId == FARM_META_USD_USDC_53
            ? SonicConstantsLib.SILO_VAULT_121_USDC
            : farmId == FARM_META_USD_SCUSD_54
                ? SonicConstantsLib.SILO_VAULT_125_SCUSD
                : SonicConstantsLib.SILO_VAULT_128_S;
        address asset = IERC4626(borrowVault).asset();
        uint expectedRevertKind = IERC20(asset).balanceOf(flashLoanVault) < IERC20(asset).balanceOf(borrowVault)
            ? REVERT_INSUFFICIENT_BALANCE
            : REVERT_NOT_ENOUGH_LIQUIDITY;

        uint[] memory maxDepositAssets = strategy.maxDepositAssets();
        for (uint i = 0; i < maxDepositAssets.length; i++) {
            maxDepositAssets[i] = maxDepositAssets[i] * 101 / 100;
        }
        _tryToDeposit(strategy, maxDepositAssets, expectedRevertKind);
        vm.revertToState(snapshot);
    }

    //endregion --------------------------------------- maxDeposit tests

    //region --------------------------------------- Internal logic
    function _currentFarmId() internal view returns (uint) {
        return IFarmingStrategy(currentStrategy).farmId();
    }

    function getUnlimitedFlashAmount() internal view returns (uint) {
        if (_currentFarmId() == FARM_METAS_S_55) {
            return 2e24; // 2 million wS
        } else {
            return 2e12; // 2 million USDC
        }
    }

    function _setUpFlashLoanVault(
        uint additionalAmount,
        ILeverageLendingStrategy.FlashLoanKind flashKindForFarm53
    ) internal returns (address) {
        uint farmId = _currentFarmId();
        if (farmId == FARM_META_USD_USDC_53) {
            address pool = flashKindForFarm53 == ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3
                ? SonicConstantsLib.POOL_ALGEBRA_WS_USDC
                : flashKindForFarm53 == ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2
                    ? SonicConstantsLib.POOL_SHADOW_CL_USDC_WETH
                    : SonicConstantsLib.BEETS_VAULT_V3;
            // Set up flash loan vault for the strategy
            _setFlashLoanVault(
                ILeverageLendingStrategy(currentStrategy),
                pool,
                pool,
                flashKindForFarm53 == ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3
                    ? uint(ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3)
                    : flashKindForFarm53 == ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2
                        ? uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2)
                        : uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1)
            );
            if (additionalAmount != 0) {
                // Add additional amount to the flash loan vault to avoid insufficient balance
                deal(SonicConstantsLib.TOKEN_USDC, pool, additionalAmount);
            }
            return pool;
        } else if (farmId == FARM_META_USD_SCUSD_54) {
            address pool = additionalAmount == 0 ? SonicConstantsLib.BEETS_VAULT_V3 : SonicConstantsLib.BEETS_VAULT;
            _setFlashLoanVault(
                ILeverageLendingStrategy(currentStrategy),
                pool,
                pool,
                pool == SonicConstantsLib.BEETS_VAULT_V3
                    ? uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1)
                    : uint(ILeverageLendingStrategy.FlashLoanKind.Default_0)
            );
            if (additionalAmount != 0) {
                // Add additional amount to the flash loan vault to avoid insufficient balance
                deal(SonicConstantsLib.TOKEN_SCUSD, pool, additionalAmount);
            }
            return pool;
        } else if (farmId == FARM_METAS_S_55) {
            address pool = additionalAmount == 0 ? SonicConstantsLib.BEETS_VAULT_V3 : SonicConstantsLib.BEETS_VAULT;
            _setFlashLoanVault(
                ILeverageLendingStrategy(currentStrategy),
                pool,
                pool,
                pool == SonicConstantsLib.BEETS_VAULT_V3
                    ? uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1)
                    : uint(ILeverageLendingStrategy.FlashLoanKind.Default_0)
            );
            if (additionalAmount != 0) {
                // Add additional amount to the flash loan vault to avoid insufficient balance
                deal(SonicConstantsLib.TOKEN_WS, pool, additionalAmount);
            }
            return pool;
        } else {
            revert("Unknown farmId");
        }
    }

    function _tryToDeposit(
        IStrategy strategy,
        uint[] memory amounts_,
        uint revertKind
    ) internal returns (uint deposited, uint values) {
        // ----------------------------- Transfer deposit amount to the strategy
        IWrappedMetaVault wrappedMetaVault = IWrappedMetaVault(
            strategy.assets()[0] == SonicConstantsLib.WRAPPED_METAVAULT_METAUSD
                ? SonicConstantsLib.WRAPPED_METAVAULT_METAUSD
                : SonicConstantsLib.WRAPPED_METAVAULT_METAS
        );

        _dealAndApprove(address(this), currentStrategy, strategy.assets(), amounts_);
        vm.prank(address(this));
        /// forge-lint: disable-next-line
        wrappedMetaVault.transfer(address(strategy), amounts_[0]);

        // ----------------------------- Try to deposit assets to the strategy
        uint valuesBefore = strategy.total();
        address vault = address(strategy.vault());
        if (revertKind == REVERT_NOT_ENOUGH_LIQUIDITY) {
            vm.expectRevert(ISilo.NotEnoughLiquidity.selector);
        }
        if (revertKind == REVERT_INSUFFICIENT_BALANCE) {
            vm.expectRevert(IControllable.InsufficientBalance.selector);
        }
        vm.prank(vault);
        strategy.depositAssets(amounts_);

        return (amounts_[0], strategy.total() - valuesBefore);
    }

    function _tryToDepositToVault(
        address vault,
        uint[] memory amounts_,
        uint revertKind
    ) internal returns (uint deposited, uint values) {
        address[] memory assets = IVault(vault).assets();
        // ----------------------------- Prepare amount on user's balance
        _dealAndApprove(address(this), vault, assets, amounts_);
        // console.log("Deposit to vault", assets[0], amounts_[0]);

        // ----------------------------- Try to deposit assets to the vault
        uint valuesBefore = IERC20(vault).balanceOf(address(this));

        if (revertKind == REVERT_NOT_ENOUGH_LIQUIDITY) {
            vm.expectRevert(ISilo.NotEnoughLiquidity.selector);
        }
        if (revertKind == REVERT_INSUFFICIENT_BALANCE) {
            vm.expectRevert(IControllable.InsufficientBalance.selector);
        }
        vm.prank(address(this));
        IStabilityVault(vault).depositAssets(assets, amounts_, 0, address(this));

        return (amounts_[0], IERC20(vault).balanceOf(address(this)) - valuesBefore);
    }

    function _tryToWithdrawAll(IStrategy strategy) internal returns (uint withdrawn) {
        address vault = strategy.vault();
        address[] memory _assets = strategy.assets();

        uint balanceBefore = IERC20(_assets[0]).balanceOf(address(this));

        uint total = strategy.total();

        vm.prank(vault);
        strategy.withdrawAssets(_assets, total, address(this));

        return IERC20(_assets[0]).balanceOf(address(this)) - balanceBefore;
    }

    /// @notice values [0...strategy.total()]
    function _tryToWithdraw(IStrategy strategy, uint values) internal returns (uint withdrawn) {
        address vault = strategy.vault();
        address[] memory _assets = strategy.assets();

        uint balanceBefore = IERC20(_assets[0]).balanceOf(address(this));

        vm.prank(vault);
        strategy.withdrawAssets(_assets, values, address(this));

        return IERC20(_assets[0]).balanceOf(address(this)) - balanceBefore;
    }

    function _tryToWithdrawFromVault(address vault, uint values) internal returns (uint withdrawn) {
        address[] memory _assets = IVault(vault).assets();

        uint balanceBefore = IERC20(_assets[0]).balanceOf(address(this));

        vm.prank(address(this));
        IStabilityVault(vault).withdrawAssets(_assets, values, new uint[](1));

        return IERC20(_assets[0]).balanceOf(address(this)) - balanceBefore;
    }

    function _dealAndApprove(address user, address spender, address[] memory assets, uint[] memory amounts) internal {
        for (uint j; j < assets.length; ++j) {
            if (assets[j] == SonicConstantsLib.WRAPPED_METAVAULT_METAUSD) {
                _getMetaTokensOnBalance(address(this), amounts[j], true, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);
            } else if (assets[j] == SonicConstantsLib.WRAPPED_METAVAULT_METAS) {
                _getMetaTokensOnBalance(address(this), amounts[j], true, SonicConstantsLib.WRAPPED_METAVAULT_METAS);
            } else {
                deal(assets[j], user, amounts[j]);
            }

            vm.prank(user);
            IERC20(assets[j]).approve(spender, amounts[j]);
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

    /// @param targetLeveragePercent The target leverage percent to set for the strategy, i.e. 85_00
    function _setTargetLeveragePercent(uint targetLeveragePercent) internal {
        ILeverageLendingStrategy strategy = ILeverageLendingStrategy(currentStrategy);
        vm.prank(IPlatform(PLATFORM).multisig());
        strategy.setTargetLeveragePercent(targetLeveragePercent);
    }

    /// @param depositParam0 - Multiplier of flash amount for borrow on deposit.
    /// @param depositParam1 - Multiplier of borrow amount to take into account max flash loan fee in maxDeposit
    function _setDepositParams(uint depositParam0, uint depositParam1) internal {
        ILeverageLendingStrategy strategy = ILeverageLendingStrategy(currentStrategy);
        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();

        params[0] = depositParam0;
        params[1] = depositParam1;

        vm.prank(IPlatform(PLATFORM).multisig());
        strategy.setUniversalParams(params, addresses);
    }

    /// @param withdrawParam0 - Multiplier of flash amount for borrow on withdraw.
    /// @param withdrawParam1 - Multiplier of amount allowed to be deposited after withdraw. Default is 100_00 == 100% (deposit forbidden)
    /// @param withdrawParam2 - allows to disable withdraw through increasing ltv if leverage is near to target
    function _setWithdrawParams(uint withdrawParam0, uint withdrawParam1, uint withdrawParam2) internal {
        ILeverageLendingStrategy strategy = ILeverageLendingStrategy(currentStrategy);
        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();

        params[2] = withdrawParam0;
        params[3] = withdrawParam1;
        params[11] = withdrawParam2;

        vm.prank(IPlatform(PLATFORM).multisig());
        strategy.setUniversalParams(params, addresses);
    }

    function _getState() internal view returns (State memory state) {
        ILeverageLendingStrategy strategy = ILeverageLendingStrategy(address(currentStrategy));

        (state.sharePrice,) = strategy.realSharePrice();

        (
            state.ltv,
            state.maxLtv,
            state.leverage,
            state.collateralAmount,
            state.debtAmount,
            state.targetLeveragePercent
        ) = strategy.health();

        state.total = IStrategy(currentStrategy).total();
        state.maxLeverage = 100_00 * 1e18 / (1e18 - state.maxLtv);
        state.targetLeverage = state.maxLeverage * state.targetLeveragePercent / 100_00;
        state.balanceAsset = IERC20(IStrategy(address(strategy)).assets()[0]).balanceOf(address(currentStrategy));
        (state.realTvl,) = strategy.realTvl();
        state.vaultBalance = IVault(IStrategy(address(strategy)).vault()).balanceOf(address(this));

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

    //endregion --------------------------------------- Internal logic

    //region --------------------------------------- Helper functions
    function _upgradeMetaVault(address platform, address metaVault_) internal {
        IMetaVaultFactory metaVaultFactory = IMetaVaultFactory(IPlatform(platform).metaVaultFactory());
        address multisig = IPlatform(platform).multisig();

        // Upgrade MetaVault to the new implementation
        address vaultImplementation = address(new MetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);

        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault_);
        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);
    }

    function upgradeWrappedMetaVault() internal {
        address multisig = IPlatform(PLATFORM).multisig();
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

    function _upgradePlatform(address multisig, address priceReader_) internal {
        // we need to skip 1 day to update the swapper
        // but we cannot simply skip 1 day, because the silo oracle will start to revert with InvalidPrice
        // vm.warp(block.timestamp - 86400);
        rewind(86400);

        IPlatform platform = IPlatform(IControllable(priceReader_).platform());

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = address(priceReader_);
        //proxies[1] = platform.swapper();
        //proxies[2] = platform.ammAdapter(keccak256(bytes(AmmAdapterIdLib.META_VAULT))).proxy;

        implementations[0] = address(new PriceReader());
        //implementations[1] = address(new Swapper());
        //implementations[2] = address(new MetaVaultAdapter());

        //vm.prank(multisig);
        // platform.cancelUpgrade();

        vm.startPrank(multisig);
        platform.announcePlatformUpgrade("2025.07.22-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }

    function _setFlashLoanVault(ILeverageLendingStrategy strategy, address vaultC, address vaultB, uint kind) internal {
        address multisig = IPlatform(platform).multisig();

        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
        params[10] = kind;
        addresses[0] = vaultC;
        addresses[1] = vaultB;

        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
    }

    function _getDiffPercent18(uint x, uint y) internal pure returns (uint) {
        if (x == 0) {
            return y == 0 ? 0 : 1e18;
        }
        return x > y ? (x - y) * 1e18 / x : (y - x) * 1e18 / x;
    }
    //endregion --------------------------------------- Helper functions

    function _changeWhitelistTransientCache(address multisig, IPriceReader priceReader) internal {
        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(currentStrategy, true);

        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(_currentMetaVault, true);

        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(SonicConstantsLib.METAVAULT_METAS, true);

        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(SonicConstantsLib.METAVAULT_METAUSD, true);
    }
}
