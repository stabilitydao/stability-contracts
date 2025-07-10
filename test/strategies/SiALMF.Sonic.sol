// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/console.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {ISilo} from "../../src/integrations/silo/ISilo.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {UniversalTest} from "../base/UniversalTest.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";

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
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        // vm.rollFork(34471950); // Jun-17-2025 09:08:37 AM +UTC
        // vm.rollFork(36717785); // Jul-01-2025 01:21:29 PM +UTC
        vm.rollFork(37477020); // Jul-07-2025 12:24:42 PM +UTC

        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
    }

    function testSiALMFSonic() public universalTest {
        _addStrategy(FARM_META_USD_USDC_53);
        //        _addStrategy(FARM_META_USD_SCUSD_54); // todo
        _addStrategy(FARM_METAS_S_55);
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
        console.log("!!!!!!!!!!!! _preDeposit START");
        uint farmId = _currentFarmId();
        if (farmId == FARM_META_USD_USDC_53 || farmId == FARM_META_USD_SCUSD_54) {
            _currentMetaVault = SonicConstantsLib.METAVAULT_metaUSD;
        } else if (farmId == FARM_METAS_S_55) {
            _currentMetaVault = SonicConstantsLib.METAVAULT_metaS;
        } else {
            revert("Unknown farmId");
        }

        IPlatform platform = IPlatform(PLATFORM); // IControllable(currentStrategy).platform());
        _upgradeMetaVault(address(platform), _currentMetaVault);

        vm.prank(platform.multisig());
        IMetaVault(_currentMetaVault).changeWhitelist(currentStrategy, true);

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

        _setUpFlashLoanVault(getUnlimitedFlashAmount(), ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2);
        console.log("!!!!!!!!!!!! _preDeposit END");
    }

    //region --------------------------------------- Strategy params tests
    function _testStrategyParams_All() internal {
        uint snapshot = vm.snapshotState();

        // --------------------------------------------- targetLeveragePercent - percent of max leverage.
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
        console.log("depositedAssets", depositedAssets);
        console.log("depositedValue", depositedValue);

        uint withdrawn1 = _tryToWithdraw(strategy, depositedValue / 2);
        vm.roll(block.number + 6);
        State memory state2 = _getState();
        console.log("withdrawn1", withdrawn1);

        uint withdrawn2 = _tryToWithdraw(strategy, depositedValue - depositedValue / 2);
        vm.roll(block.number + 6);
        State memory state3 = _getState();
        console.log("withdrawn2", withdrawn2);

        vm.revertToState(snapshot);

        // --------------------------------------------- Check results
        assertEq(depositedAssets, amountsToDeposit[0], "Deposited amount should be equal to amountsToDeposit");
        if (freeFlashLoan_) {
            assertLt(
                _getDiffPercent18(depositedAssets, withdrawn1 + withdrawn2),
                1e18 / 100, // less 1%
                "Withdrawn amount should be equal to deposited amount"
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
        assertEq(state1.total, state0.total + depositedValue, "Total should increase on expected value after deposit");
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
            "Withdrawn amount should be close to deposited amount"
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
        uint snapshot = vm.snapshot();
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
        uint snapshot = vm.snapshot();
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
        uint snapshot = vm.snapshot();
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
        uint snapshot = vm.snapshot();
        address flashLoanVault = _setUpFlashLoanVault(0, ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2);

        uint farmId = _currentFarmId();
        address borrowVault = farmId == FARM_META_USD_USDC_53
            ? SonicConstantsLib.SILO_VAULT_121_USDC
            : farmId == FARM_META_USD_SCUSD_54 ? SonicConstantsLib.SILO_VAULT_125_scUSD : SonicConstantsLib.SILO_VAULT_128_S;
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
                deal(SonicConstantsLib.TOKEN_scUSD, pool, additionalAmount);
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
                deal(SonicConstantsLib.TOKEN_wS, pool, additionalAmount);
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
            strategy.assets()[0] == SonicConstantsLib.WRAPPED_METAVAULT_metaUSD
                ? SonicConstantsLib.WRAPPED_METAVAULT_metaUSD
                : SonicConstantsLib.WRAPPED_METAVAULT_metaS
        );

        _dealAndApprove(address(this), currentStrategy, strategy.assets(), amounts_);
        vm.prank(address(this));
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

    function _dealAndApprove(address user, address spender, address[] memory assets, uint[] memory amounts) internal {
        for (uint j; j < assets.length; ++j) {
            if (assets[j] == SonicConstantsLib.WRAPPED_METAVAULT_metaUSD) {
                _getMetaTokensOnBalance(address(this), amounts[j], true, SonicConstantsLib.WRAPPED_METAVAULT_metaUSD);
            } else if (assets[j] == SonicConstantsLib.WRAPPED_METAVAULT_metaS) {
                _getMetaTokensOnBalance(address(this), amounts[j], true, SonicConstantsLib.WRAPPED_METAVAULT_metaS);
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
        address asset = address(metaVault) == SonicConstantsLib.METAVAULT_metaUSD
            ? SonicConstantsLib.TOKEN_USDC
            : SonicConstantsLib.TOKEN_wS;

        // we don't know exact amount of USDC required to receive exact amountMetaVaultTokens
        // so we deposit a bit large amount of USDC
        address[] memory _assets = metaVault.assetsForDeposit();
        uint[] memory amountsMax = new uint[](1);
        amountsMax[0] = address(metaVault) == SonicConstantsLib.METAVAULT_metaUSD
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

        (state.ltv, state.maxLtv, state.leverage, state.collateralAmount, state.debtAmount, state.targetLeveragePercent)
        = strategy.health();

        state.total = IStrategy(currentStrategy).total();
        state.maxLeverage = 100_00 * 1e18 / (1e18 - state.maxLtv);
        state.targetLeverage = state.maxLeverage * state.targetLeveragePercent / 100_00;
        state.balanceAsset = IERC20(IStrategy(address(strategy)).assets()[0]).balanceOf(address(currentStrategy));

        console.log("targetLeverage, leverage, total", state.targetLeverage, state.leverage, state.total);

        //        console.log("ltv", state.ltv);
        //        console.log("maxLtv", state.maxLtv);
        //        console.log("targetLeverage", state.targetLeverage);
        //        console.log("leverage", state.leverage);
        //        console.log("total", state.total);
        //        console.log("collateralAmount", state.collateralAmount);
        //        console.log("debtAmount", state.debtAmount);
        //        console.log("targetLeveragePercent", state.targetLeveragePercent);
        //        console.log("maxLeverage", state.maxLeverage);
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

    function _setFlashLoanVault(
        ILeverageLendingStrategy strategy,
        address vaultC,
        address vaultB,
        uint kind
    ) internal {
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
}
