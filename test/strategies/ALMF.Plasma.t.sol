// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";
import {PlasmaSetup} from "../base/chains/PlasmaSetup.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {UniversalTest} from "../base/UniversalTest.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";
import {IAaveAddressProvider} from "../../src/integrations/aave/IAaveAddressProvider.sol";
import {IAavePriceOracle} from "../../src/integrations/aave/IAavePriceOracle.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";
import {FixedPointMathLib} from "../../lib/solady/src/utils/FixedPointMathLib.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
// import {IAaveDataProvider} from "../../src/integrations/aave/IAaveDataProvider.sol";
import {AaveLeverageMerklFarmStrategy} from "../../src/strategies/AaveLeverageMerklFarmStrategy.sol";
import {console} from "forge-std/console.sol";
import {SharedFarmMakerLib} from "../../chains/shared/SharedFarmMarketLib.sol";
import {IAavePool32} from "../../src/integrations/aave32/IPool32.sol";

contract ALMFStrategyPlasmaTest is PlasmaSetup, UniversalTest {
    uint public constant REVERT_NO = 0;
    uint public constant REVERT_NOT_ENOUGH_LIQUIDITY = 1;
    uint public constant REVERT_INSUFFICIENT_BALANCE = 2;

    uint internal constant INDEX_INIT_0 = 0;
    uint internal constant INDEX_AFTER_DEPOSIT_1 = 1;
    uint internal constant INDEX_AFTER_WAIT_2 = 2;
    uint internal constant INDEX_AFTER_HARDWORK_3 = 3;
    uint internal constant INDEX_AFTER_WITHDRAW_4 = 4;

    uint internal constant DEFAULT_TARGET_LEVERAGE_2 = 2_0000; // 2x
    uint internal constant DEFAULT_LTV1_MINUS_LTV0_2 = 500; // 5.00%

    uint internal constant DEFAULT_TARGET_LEVERAGE_3 = 3_0000; // 3x
    uint internal constant DEFAULT_LTV1_MINUS_LTV0_3 = 300; // 3.00%

    uint internal constant DEFAULT_TARGET_LEVERAGE_9 = 9_0000; // 9x
    uint internal constant DEFAULT_LTV1_MINUS_LTV0_9 = 15; // 0.15%

    uint internal constant DEFAULT_TARGET_LEVERAGE_10 = 10_0000; // 10x
    uint internal constant DEFAULT_LTV1_MINUS_LTV0_10 = 10; // 0.10%

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
        uint strategyBalanceAsset;
        uint userBalanceAsset;
        uint realTvl;
        uint realSharePrice;
        uint vaultBalance;
        address[] revenueAssets;
        uint[] revenueAmounts;
    }

    uint8 internal constant E_MODE_CATEGORY_ID_NOT_USED = 0;
    uint8 internal constant E_MODE_CATEGORY_ID_USDE_STABLECOINS = 1;
    uint8 internal constant E_MODE_CATEGORY_ID_SUSDE_STABLECOINS = 2;
    uint8 internal constant E_MODE_CATEGORY_ID_WEETH_WETH = 3;
    uint8 internal constant E_MODE_CATEGORY_ID_WEETH_STABLECOINS = 4;

    // uint internal constant FORK_BLOCK = 6452516; // Nov-17-2025 12:36:59 UTC
    uint internal constant FORK_BLOCK = 7041595; // Nov-24-2025 08:16:08 UTC

    /// @notice Farm Id of the farm WETH-USDT0, leverage 3
    uint internal farmIdWethUsdt3;
    uint internal farmWeethWeth10;
    uint internal farmSusdeUsdt9;
    uint internal farmWeethUsdt2;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("PLASMA_RPC_URL"), FORK_BLOCK));

        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;

        // ALMF uses real share price as share price
        // so it cannot initialize share price during deposit.
        // It sets initial value of share price in first claimRevenue.
        // As result, following check is failed in universal test:
        // "Universal test: estimated totalRevenueUSD is zero"
        // So, we should disable it by setting allowZeroTotalRevenueUSD.
        // And make all checks in additional tests instead.
        allowZeroTotalRevenueUSD = true;

        // _upgradePlatform(platform.multisig(), IPlatform(platform).priceReader());
    }

    //region --------------------------------------- Universal test
    function testALMFPlasma() public universalTest {
        _addRoutes();

        farmIdWethUsdt3 = _addFarmWethUsdt3NoEMode();
        farmWeethWeth10 = _addFarmWeethWeth10();
        farmSusdeUsdt9 = _addFarmSusdeUsdt9();
        farmWeethUsdt2 = _addFarmWeethUsdt2NoRewards();

        _addStrategy(farmIdWethUsdt3);
        _addStrategy(farmSusdeUsdt9);
        _addStrategy(farmWeethWeth10);
        _addStrategy(farmWeethUsdt2);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.AAVE_LEVERAGE_MERKL_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }

    function _preDeposit() internal override {
        uint farmId = IFarmingStrategy(currentStrategy).farmId();
        if (farmId == farmIdWethUsdt3) {
            console.log("FARM WETH-USDT0 leverage 3");
            _preDepositForFarmWethUsdt3();
        } else if (farmId == farmWeethWeth10) {
            console.log("FARM WEETH-WETH leverage 10");
            _preDepositForFarmWeethWeth10();
        } else if (farmId == farmSusdeUsdt9) {
            console.log("FARM SUSDE-USDT leverage 9");
            _preDepositForFarmSusdeUsdt9();
        } else if (farmId == farmWeethUsdt2) {
            console.log("FARM WEETH-USDT leverage 2 no rewards");
            _preDepositForFarmWeethUsdt2NoRewards();
        }
    }

    function _preHardWork() internal override {
        for (uint i; i < 2; ++i) {
            // emulate merkl rewards
            uint farmId = IFarmingStrategy(currentStrategy).farmId();
            if (farmId == farmIdWethUsdt3) {
                _preHardWorkForFarmWethUsdt3();
            } else if (farmId == farmWeethWeth10) {
                _preHardWorkForFarmWeethWeth10();
            } else if (farmId == farmSusdeUsdt9) {
                _preHardWorkForFarmSusdeUsdt9();
            } else if (farmId == farmWeethUsdt2) {
                _preHardWorkForFarmWeethUsdt2NoRewards();
            }

            if (i == 0) {
                // Make first hardwork to initialize share price, APR is 0
                // Next hardwork in universal test will be able to show not zero APR
                vm.prank(platform.multisig());
                IVault(IStrategy(currentStrategy).vault()).doHardWork();
                _skip(duration1 + duration2, 0);
            }
        }
    }

    //endregion --------------------------------------- Universal test

    //region --------------------------------------- _preDeposit overrides for farms
    function _preDepositForFarmWethUsdt3() internal {
        uint snapshot = vm.snapshotState();
        // thresholds
        vm.prank(platform.multisig());
        AaveLeverageMerklFarmStrategy(currentStrategy).setThreshold(PlasmaConstantsLib.TOKEN_WETH, 1e12);
        vm.prank(platform.multisig());
        AaveLeverageMerklFarmStrategy(currentStrategy).setThreshold(PlasmaConstantsLib.TOKEN_USDT0, 1e6);

        // initial supply
        _tryToDepositToVault(IStrategy(currentStrategy).vault(), 0.1e18, REVERT_NO, makeAddr("initial supplier"));

        // check revenue (replacement for "Universal test: estimated totalRevenueUSD is zero")
        _testDepositTwoHardworks();

        // set TL, deposit, change TL, withdraw/deposit => leverage was changed toward new TL
        _testDepositChangeLtvWithdraw();
        _testDepositChangeLtvDeposit();

        // check deposit-wait 30 days-hardwork-withdraw results
        _testDepositWaitHardworkWithdraw();

        // explicitly check possible swaps
        assertGt(_swap(PlasmaConstantsLib.TOKEN_SUSDE, PlasmaConstantsLib.TOKEN_USDE, 1e18), 0, "susde=>usde");
        assertGt(_swap(PlasmaConstantsLib.TOKEN_USDE, PlasmaConstantsLib.TOKEN_USDT0, 1e18), 0, "usde=>usdt0");
        assertGt(_swap(PlasmaConstantsLib.TOKEN_WETH, PlasmaConstantsLib.TOKEN_WEETH, 0.1e18), 0, "weth=>weeth");
        assertGt(_swap(PlasmaConstantsLib.TOKEN_WEETH, PlasmaConstantsLib.TOKEN_WETH, 0.1e18), 0, "weeth=>weth");
        assertGt(_swap(PlasmaConstantsLib.TOKEN_WEETH, PlasmaConstantsLib.TOKEN_USDT0, 0.1e18), 0, "weeth=>usdt0");

        vm.revertToState(snapshot);
    }

    function _preDepositForFarmSusdeUsdt9() internal {
        // ---------------- Setup thresholds required by universal test
        vm.prank(platform.multisig());
        AaveLeverageMerklFarmStrategy(currentStrategy).setThreshold(PlasmaConstantsLib.TOKEN_SUSDE, 1e12);
        vm.prank(platform.multisig());
        AaveLeverageMerklFarmStrategy(currentStrategy).setThreshold(PlasmaConstantsLib.TOKEN_USDT0, 1e6);

        // ---------------- Additional tests
        uint snapshot = vm.snapshotState();

        _tryToDepositToVault(IStrategy(currentStrategy).vault(), 100e18, REVERT_NO, address(this));

        IAavePool32.EModeCategoryLegacy memory eModeData =
            IAavePool32(PlasmaConstantsLib.AAVE_V3_POOL).getEModeCategoryData(E_MODE_CATEGORY_ID_SUSDE_STABLECOINS);

        (, uint maxLtv,,,,) = AaveLeverageMerklFarmStrategy(currentStrategy).health();
        assertEq(maxLtv, eModeData.ltv, "max ltv for e-mode matches");

        // see https://app.aave.com/reserve-overview/?underlyingAsset=0x211cc4dd073734da055fbf44a2b4667d5e5fe5d2&marketName=proto_plasma_v3
        assertEq(maxLtv, 90_00, "max ltv is 90%");

        vm.revertToState(snapshot);
    }

    function _preDepositForFarmWeethWeth10() internal {
        // ---------------- thresholds
        vm.prank(platform.multisig());
        AaveLeverageMerklFarmStrategy(currentStrategy).setThreshold(PlasmaConstantsLib.TOKEN_WEETH, 1e14);
        vm.prank(platform.multisig());
        AaveLeverageMerklFarmStrategy(currentStrategy).setThreshold(PlasmaConstantsLib.TOKEN_WETH, 1e14);

        // ---------------- Additional tests
        uint snapshot = vm.snapshotState();

        _tryToDepositToVault(IStrategy(currentStrategy).vault(), 1e18, REVERT_NO, address(this));

        IAavePool32.EModeCategoryLegacy memory eModeData =
            IAavePool32(PlasmaConstantsLib.AAVE_V3_POOL).getEModeCategoryData(E_MODE_CATEGORY_ID_WEETH_WETH);

        (, uint maxLtv,,,,) = AaveLeverageMerklFarmStrategy(currentStrategy).health();
        assertEq(maxLtv, eModeData.ltv, "max ltv for e-mode matches");

        // see https://app.aave.com/reserve-overview/?underlyingAsset=0x211cc4dd073734da055fbf44a2b4667d5e5fe5d2&marketName=proto_plasma_v3
        assertEq(maxLtv, 93_00, "max ltv is 93%");

        vm.revertToState(snapshot);
    }

    function _preDepositForFarmWeethUsdt2NoRewards() internal {
        // ---------------- thresholds
        vm.prank(platform.multisig());
        AaveLeverageMerklFarmStrategy(currentStrategy).setThreshold(PlasmaConstantsLib.TOKEN_WEETH, 1e12);
        vm.prank(platform.multisig());
        AaveLeverageMerklFarmStrategy(currentStrategy).setThreshold(PlasmaConstantsLib.TOKEN_USDT0, 1e6);

        // ---------------- Additional tests
        uint snapshot = vm.snapshotState();

        _tryToDepositToVault(IStrategy(currentStrategy).vault(), 1e18, REVERT_NO, address(this));

        IAavePool32.EModeCategoryLegacy memory eModeData =
            IAavePool32(PlasmaConstantsLib.AAVE_V3_POOL).getEModeCategoryData(E_MODE_CATEGORY_ID_WEETH_STABLECOINS);

        (, uint maxLtv,,,,) = AaveLeverageMerklFarmStrategy(currentStrategy).health();
        assertEq(maxLtv, eModeData.ltv, "max ltv for e-mode matches");

        // see https://app.aave.com/reserve-overview/?underlyingAsset=0x211cc4dd073734da055fbf44a2b4667d5e5fe5d2&marketName=proto_plasma_v3
        assertEq(maxLtv, 75_00, "max ltv is 75%");

        vm.revertToState(snapshot);
    }

    //endregion --------------------------------------- _preDeposit overrides for farms

    //region --------------------------------------- _preHardWork overrides for farms
    function _preHardWorkForFarmWethUsdt3() internal {
        deal(PlasmaConstantsLib.TOKEN_USDT0, currentStrategy, 1e6);
        deal(PlasmaConstantsLib.TOKEN_WXPL, currentStrategy, 0.1e18);
    }

    function _preHardWorkForFarmSusdeUsdt9() internal {
        // !TODO: deal(PlasmaConstantsLib.TOKEN_WAPLAUSDE, currentStrategy, 100e18);
    }

    function _preHardWorkForFarmWeethWeth10() internal {
        deal(PlasmaConstantsLib.TOKEN_WXPL, currentStrategy, 10e18);
    }

    function _preHardWorkForFarmWeethUsdt2NoRewards() internal {
        deal(PlasmaConstantsLib.TOKEN_WXPL, currentStrategy, 10e18);
    }

    //endregion --------------------------------------- _preHardWork overrides for farms

    //region --------------------------------------- Farms
    /// @notice WETH-USDT0, leverage 3
    function _addFarmWethUsdt3NoEMode() internal returns (uint farmId) {
        address[] memory rewards = new address[](2);
        rewards[0] = PlasmaConstantsLib.TOKEN_USDT0;
        rewards[1] = PlasmaConstantsLib.TOKEN_WXPL;

        (uint minLtv, uint maxLtv) = getMinMaxLtv(DEFAULT_TARGET_LEVERAGE_3, DEFAULT_LTV1_MINUS_LTV0_3);

        IFactory.Farm[] memory farms = new IFactory.Farm[](1);
        farms[0] = SharedFarmMakerLib._makeAaveLeverageMerklFarm(
            PlasmaConstantsLib.AAVE_V3_POOL_WETH,
            PlasmaConstantsLib.AAVE_V3_POOL_USDT0,
            PlasmaConstantsLib.POOL_WXPL_USDT0,
            rewards,
            minLtv,
            maxLtv,
            uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2),
            E_MODE_CATEGORY_ID_NOT_USED
        );

        vm.startPrank(platform.multisig());
        factory.addFarms(farms);

        return factory.farmsLength() - 1;
    }

    function _addFarmWeethWeth10() internal returns (uint farmId) {
        address[] memory rewards = new address[](1);
        rewards[0] = PlasmaConstantsLib.TOKEN_WXPL;

        (uint minLtv, uint maxLtv) = getMinMaxLtv(DEFAULT_TARGET_LEVERAGE_10, DEFAULT_LTV1_MINUS_LTV0_10);

        IFactory.Farm[] memory farms = new IFactory.Farm[](1);
        farms[0] = SharedFarmMakerLib._makeAaveLeverageMerklFarm(
            PlasmaConstantsLib.AAVE_V3_POOL_WEETH,
            PlasmaConstantsLib.AAVE_V3_POOL_WETH,
            PlasmaConstantsLib.POOL_OKU_TRADE_USDT0_WETH,
            rewards,
            minLtv,
            maxLtv,
            uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2),
            E_MODE_CATEGORY_ID_WEETH_WETH
        );

        vm.startPrank(platform.multisig());
        factory.addFarms(farms);

        return factory.farmsLength() - 1;
    }

    function _addFarmSusdeUsdt9() internal returns (uint farmId) {
        //        address[] memory rewards = new address[](1);
        //        rewards[0] = PlasmaConstantsLib.TOKEN_WAPLAUSDE;
        address[] memory rewards;

        (uint minLtv, uint maxLtv) = getMinMaxLtv(DEFAULT_TARGET_LEVERAGE_9, DEFAULT_LTV1_MINUS_LTV0_9);

        IFactory.Farm[] memory farms = new IFactory.Farm[](1);
        farms[0] = SharedFarmMakerLib._makeAaveLeverageMerklFarm(
            PlasmaConstantsLib.AAVE_V3_POOL_SUSDE,
            PlasmaConstantsLib.AAVE_V3_POOL_USDT0,
            PlasmaConstantsLib.POOL_WXPL_USDT0,
            rewards,
            minLtv,
            maxLtv,
            uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2),
            E_MODE_CATEGORY_ID_SUSDE_STABLECOINS
        );

        vm.startPrank(platform.multisig());
        factory.addFarms(farms);

        return factory.farmsLength() - 1;
    }

    function _addFarmSusdeUsde9() internal returns (uint farmId) {
        address[] memory rewards = new address[](1);
        rewards[0] = PlasmaConstantsLib.TOKEN_WAPLAUSDE;

        (uint minLtv, uint maxLtv) = getMinMaxLtv(DEFAULT_TARGET_LEVERAGE_9, DEFAULT_LTV1_MINUS_LTV0_9);

        IFactory.Farm[] memory farms = new IFactory.Farm[](1);
        farms[0] = SharedFarmMakerLib._makeAaveLeverageMerklFarm(
            PlasmaConstantsLib.AAVE_V3_POOL_SUSDE,
            PlasmaConstantsLib.AAVE_V3_POOL_USDE,
            PlasmaConstantsLib.POOL_WXPL_USDT0, // todo we need to get flash in USDe
            rewards,
            minLtv,
            maxLtv,
            uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2),
            E_MODE_CATEGORY_ID_SUSDE_STABLECOINS
        );

        vm.startPrank(platform.multisig());
        factory.addFarms(farms);

        return factory.farmsLength() - 1;
    }

    /// @notice Test real farm but without rewards
    function _addFarmWeethUsdt2NoRewards() internal returns (uint farmId) {
        address[] memory rewards; // no rewards - for test purposes

        (uint minLtv, uint maxLtv) = getMinMaxLtv(DEFAULT_TARGET_LEVERAGE_2, DEFAULT_LTV1_MINUS_LTV0_2);

        IFactory.Farm[] memory farms = new IFactory.Farm[](1);
        farms[0] = SharedFarmMakerLib._makeAaveLeverageMerklFarm(
            PlasmaConstantsLib.AAVE_V3_POOL_WEETH,
            PlasmaConstantsLib.AAVE_V3_POOL_USDT0,
            PlasmaConstantsLib.POOL_WXPL_USDT0,
            rewards,
            minLtv,
            maxLtv,
            uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2),
            E_MODE_CATEGORY_ID_WEETH_STABLECOINS
        );

        vm.startPrank(platform.multisig());
        factory.addFarms(farms);

        return factory.farmsLength() - 1;
    }

    //endregion --------------------------------------- Farms

    //region --------------------------------------- Unit tests
    function testGetMinMaxLtv() public pure {
        (uint minLtv, uint maxLtv) = getMinMaxLtv(10_0000, 10);
        assertEq(minLtv, 8995, "min ltv 10");
        assertEq(maxLtv, 9005, "max ltv 10");

        (minLtv, maxLtv) = getMinMaxLtv(3_0000, 500);
        assertEq(minLtv, 6399, "min ltv 3");
        assertEq(maxLtv, 6899, "max ltv 3");
    }

    //endregion --------------------------------------- Unit tests

    //region --------------------------------------- Additional tests
    function _testDepositTwoHardworks() internal {
        uint amount = 1e18;

        uint priceWeth8 = _getWethPrice8();

        IStrategy strategy = IStrategy(currentStrategy);

        // --------------------------------------------- Deposit
        State memory stateAfterDeposit = _getState();
        _tryToDepositToVault(strategy.vault(), amount, REVERT_NO, address(this));
        vm.roll(block.number + 6);

        // --------------------------------------------- Hardwork 1
        _skip(1 days, 0);
        deal(PlasmaConstantsLib.TOKEN_USDT0, currentStrategy, 100e6);

        vm.prank(platform.multisig());
        IVault(strategy.vault()).doHardWork();

        State memory stateAfterHW1 = _getState();

        // --------------------------------------------- Hardwork 2
        _skip(1 days, 0);
        deal(PlasmaConstantsLib.TOKEN_USDT0, currentStrategy, 300e6);

        vm.prank(platform.multisig());
        IVault(strategy.vault()).doHardWork();

        State memory stateAfterHW2 = _getState();

        assertEq(
            stateAfterDeposit.revenueAmounts[0],
            0,
            "Revenue before first claimReview is 0 because share price is not initialized yet"
        );
        assertApproxEqRel(
            stateAfterHW1.revenueAmounts[0] * priceWeth8 * 1e6 / 1e8 / 1e18,
            100e6,
            20e16,
            "Revenue after first hardwork is ~$100"
        );
        assertApproxEqRel(
            stateAfterHW2.revenueAmounts[0] * priceWeth8 * 1e6 / 1e8 / 1e18,
            300e6,
            20e16,
            "Revenue after first hardwork is ~$300"
        );
    }

    function _testDepositChangeLtvWithdraw() internal {
        {
            (, State memory stateAfterDeposit, State memory stateAfterWithdraw) =
                _depositChangeLtvWithdraw(49_00, 50_97, 52_00, 51_97);

            assertApproxEqRel(
                stateAfterDeposit.leverage,
                stateAfterDeposit.targetLeverage,
                1e16,
                "Leverage after deposit should be equal to target 111"
            );
            assertLt(
                stateAfterDeposit.leverage,
                stateAfterWithdraw.targetLeverage,
                "leverage before withdraw less than target"
            );
            assertGt(stateAfterWithdraw.leverage, stateAfterDeposit.leverage, "withdraw increased the leverage");
        }
        {
            (, State memory stateAfterDeposit, State memory stateAfterWithdraw) =
                _depositChangeLtvWithdraw(49_00, 50_97, 47_00, 48_97);

            assertApproxEqRel(
                stateAfterDeposit.leverage,
                stateAfterDeposit.targetLeverage,
                1e16,
                "Leverage after deposit should be equal to target 222"
            );
            assertGt(
                stateAfterDeposit.leverage,
                stateAfterWithdraw.targetLeverage,
                "leverage before withdraw greater than target"
            );
            assertLt(stateAfterWithdraw.leverage, stateAfterDeposit.leverage, "withdraw decreased the leverage");
        }
    }

    function _testDepositChangeLtvDeposit() internal {
        {
            (, State memory stateAfterDeposit, State memory stateAfterDeposit2) =
                _depositChangeLtvDeposit(49_00, 50_97, 52_00, 51_97);

            assertApproxEqRel(
                stateAfterDeposit.leverage,
                stateAfterDeposit.targetLeverage,
                1e16,
                "Leverage after deposit should be equal to target 333"
            );
            assertLt(
                stateAfterDeposit.leverage,
                stateAfterDeposit2.targetLeverage,
                "leverage before withdraw less than target"
            );
            assertGt(stateAfterDeposit2.leverage, stateAfterDeposit.leverage, "deposit2 increased the leverage");
        }
        {
            (, State memory stateAfterDeposit, State memory stateAfterDeposit2) =
                _depositChangeLtvDeposit(49_00, 50_97, 47_00, 48_97);

            assertApproxEqRel(
                stateAfterDeposit.leverage,
                stateAfterDeposit.targetLeverage,
                1e16,
                "Leverage after deposit should be equal to target 444"
            );
            assertGt(
                stateAfterDeposit.leverage,
                stateAfterDeposit2.targetLeverage,
                "leverage before deposit2 greater than target"
            );
            assertLt(stateAfterDeposit2.leverage, stateAfterDeposit.leverage, "deposit2 decreased the leverage");
        }
    }

    function _testDepositWithdrawUsingFlashLoan(
        address flashLoanVault,
        ILeverageLendingStrategy.FlashLoanKind kind_
    ) internal {
        uint snapshot = vm.snapshotState();
        _setUpFlashLoanVault(flashLoanVault, kind_);

        uint amount = 1e18;
        State[] memory states = _depositWithdraw(amount, PlasmaConstantsLib.TOKEN_USDT0, 0, 0, false);
        vm.revertToState(snapshot);

        assertApproxEqRel(
            states[INDEX_AFTER_WITHDRAW_4].total,
            states[INDEX_INIT_0].total,
            states[INDEX_INIT_0].total / 100_000,
            "Total should return back to prev value"
        );
        assertApproxEqRel(states[4].userBalanceAsset, amount, amount / 50, "User shouldn't loss more than 2%");
    }

    function _testDepositWaitHardworkWithdraw() internal {
        uint amount = 1e18;

        // --------------------------------------------- Deposit+withdraw without hardwork
        uint snapshot = vm.snapshotState();
        State[] memory statesInstant = _depositWithdraw(amount, PlasmaConstantsLib.TOKEN_USDT0, 0, 0, true);
        vm.revertToState(snapshot);

        // --------------------------------------------- Deposit, wait, [no rewards], hardwork, withdraw
        snapshot = vm.snapshotState();
        State[] memory statesHW1 = _depositWithdraw(amount, PlasmaConstantsLib.TOKEN_USDT0, 0, 1 days, true);
        vm.revertToState(snapshot);

        // --------------------------------------------- Deposit, wait, rewards, hardwork, withdraw
        snapshot = vm.snapshotState();
        State[] memory statesHW2 = _depositWithdraw(amount, PlasmaConstantsLib.TOKEN_USDT0, 100e6, 1 days, true);
        vm.revertToState(snapshot);

        // --------------------------------------------- Get WETH price
        uint wethPrice = _getWethPrice8();

        // --------------------------------------------- Compare results
        assertApproxEqAbs(
            statesHW2[INDEX_AFTER_HARDWORK_3].total - statesInstant[INDEX_AFTER_HARDWORK_3].total,
            100e18,
            5e18,
            "_testDepositWaitHardworkWithdraw.total is increased on rewards amount - fees"
        );
        assertLt(
            statesHW1[INDEX_AFTER_HARDWORK_3].total,
            statesInstant[INDEX_AFTER_HARDWORK_3].total,
            "_testDepositWaitHardworkWithdraw.total is decreased because the borrow rate exceeds supply rate"
        );

        assertLt(
            statesHW1[INDEX_AFTER_WITHDRAW_4].userBalanceAsset,
            statesInstant[INDEX_AFTER_WITHDRAW_4].userBalanceAsset,
            "_testDepositWaitHardworkWithdraw.user lost some amount because of borrow rate"
        );
        assertApproxEqRel(
            statesHW2[INDEX_AFTER_WITHDRAW_4].userBalanceAsset,
            100e18 / wethPrice * 1e8 + statesInstant[INDEX_AFTER_WITHDRAW_4].userBalanceAsset,
            5e16, //  < 3%
            "_testDepositWaitHardworkWithdraw.user received almost all rewards"
        );
    }

    function _testMaxDepositAndMaxWithdraw() internal view {
        assertEq(IStrategy(currentStrategy).maxDepositAssets().length, 0, "any amount can be deposited");
        assertEq(IStrategy(currentStrategy).maxWithdrawAssets(0).length, 0, "any amount can be withdrawn");
    }

    //endregion --------------------------------------- Additional tests

    //region --------------------------------------- Test implementations
    function _depositChangeLtvWithdraw(
        uint minLtv0,
        uint maxLtv0,
        uint minLtv1,
        uint maxLtv1
    ) internal returns (State memory stateInitial, State memory stateAfterDeposit, State memory stateAfterWithdraw) {
        uint snapshot = vm.snapshotState();
        address vault = IStrategy(currentStrategy).vault();
        _setMinMaxLtv(minLtv0, maxLtv0);

        stateInitial = _getState();

        _tryToDepositToVault(vault, 1e18, 0, address(this));
        stateAfterDeposit = _getState();

        vm.roll(block.number + 6);

        _setMinMaxLtv(minLtv1, maxLtv1);

        _tryToWithdrawFromVault(vault, IVault(vault).balanceOf(address(this)));
        stateAfterWithdraw = _getState();

        vm.revertToState(snapshot);
    }

    function _depositChangeLtvDeposit(
        uint minLtv0,
        uint maxLtv0,
        uint minLtv1,
        uint maxLtv1
    ) internal returns (State memory stateInitial, State memory stateAfterDeposit, State memory stateAfterDeposit2) {
        uint snapshot = vm.snapshotState();
        address vault = IStrategy(currentStrategy).vault();
        _setMinMaxLtv(minLtv0, maxLtv0);

        stateInitial = _getState();

        _tryToDepositToVault(vault, 1e18, 0, address(this));
        stateAfterDeposit = _getState();

        vm.roll(block.number + 6);

        _setMinMaxLtv(minLtv1, maxLtv1);

        _tryToDepositToVault(vault, 1e18, 0, address(this));
        stateAfterDeposit2 = _getState();

        vm.revertToState(snapshot);
    }

    /// @notice Deposit, check state, withdraw all, check state
    /// @return states [initial state, state after deposit, state after waiting, state after hardwork, state after withdraw]
    function _depositWithdraw(
        uint amount,
        address rewards,
        uint rewardsAmount,
        uint waitSec,
        bool hardworkBeforeWithdraw
    ) internal returns (State[] memory states) {
        uint snapshot = vm.snapshotState();
        states = new State[](5);

        IStrategy strategy = IStrategy(currentStrategy);

        // --------------------------------------------- Deposit
        states[0] = _getState();
        (uint depositedAssets,) = _tryToDepositToVault(strategy.vault(), amount, REVERT_NO, address(this));
        vm.roll(block.number + 6);
        states[1] = _getState();

        _skip(waitSec, 0);
        states[2] = _getState();

        // --------------------------------------------- Hardwork
        if (rewardsAmount != 0) {
            // emulate merkl rewards
            deal(rewards, currentStrategy, rewardsAmount);
        }

        if (hardworkBeforeWithdraw) {
            vm.prank(platform.multisig());
            IVault(strategy.vault()).doHardWork();
        }
        states[3] = _getState();

        // --------------------------------------------- Withdraw
        _tryToWithdrawFromVault(strategy.vault(), states[1].vaultBalance - states[0].vaultBalance);
        vm.roll(block.number + 6);
        states[4] = _getState();

        vm.revertToState(snapshot);

        assertLt(states[0].total, states[1].total, "Total should increase after deposit");
        assertEq(depositedAssets, amount, "Deposited amount should be equal to amountsToDeposit");
    }

    //endregion --------------------------------------- Test implementations

    //region --------------------------------------- Internal logic
    function _swap(address from, address to, uint amountIn) internal returns (uint amountOut) {
        uint balanceBefore = IERC20(to).balanceOf(address(this));
        deal(from, address(this), amountIn);
        ISwapper swapper = ISwapper(IPlatform(platform).swapper());

        IERC20(from).approve(address(swapper), amountIn);

        swapper.swap(from, to, amountIn, 1000);
        return IERC20(to).balanceOf(address(this)) - balanceBefore;
    }

    function _currentFarmId() internal view returns (uint) {
        return IFarmingStrategy(currentStrategy).farmId();
    }

    function _tryToDepositToVault(
        address vault,
        uint amount,
        uint revertKind,
        address user
    ) internal returns (uint deposited, uint depositedValue) {
        address[] memory assets = IVault(vault).assets();
        uint[] memory amountsToDeposit = new uint[](1);
        amountsToDeposit[0] = amount;

        // ----------------------------- Prepare amount on user's balance
        _dealAndApprove(user, vault, assets, amountsToDeposit);
        // console.log("Deposit to vault", assets[0], amounts_[0]);

        uint balanceBefore = IVault(vault).balanceOf(user);
        // ----------------------------- Try to deposit assets to the vault
        // todo
        //        if (revertKind == REVERT_NOT_ENOUGH_LIQUIDITY) {
        //            vm.expectRevert(ISilo.NotEnoughLiquidity.selector);
        //        }
        if (revertKind == REVERT_INSUFFICIENT_BALANCE) {
            vm.expectRevert(IControllable.InsufficientBalance.selector);
        }
        vm.prank(user);
        IStabilityVault(vault).depositAssets(assets, amountsToDeposit, 0, user);

        return (amountsToDeposit[0], IVault(vault).balanceOf(user) - balanceBefore);
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
            deal(assets[j], user, amounts[j]);

            vm.prank(user);
            IERC20(assets[j]).approve(spender, amounts[j]);
        }
    }

    /// @param depositParam0 - Multiplier of flash amount for borrow on deposit.
    /// @param depositParam1 - Multiplier of borrow amount to take into account max flash loan fee in maxDeposit
    function _setDepositParams(uint depositParam0, uint depositParam1) internal {
        ILeverageLendingStrategy strategy = ILeverageLendingStrategy(currentStrategy);
        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();

        params[0] = depositParam0;
        params[1] = depositParam1;

        vm.prank(platform.multisig());
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

        vm.prank(platform.multisig());
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
        state.maxLeverage = 100_00 * 1e4 / (1e4 - state.maxLtv);
        state.targetLeverage = state.maxLeverage * state.targetLeveragePercent / 100_00;
        state.strategyBalanceAsset =
            IERC20(IStrategy(address(strategy)).assets()[0]).balanceOf(address(currentStrategy));
        state.userBalanceAsset = IERC20(IStrategy(address(strategy)).assets()[0]).balanceOf(address(address(this)));
        (state.realTvl,) = strategy.realTvl();
        (state.realSharePrice,) = strategy.realSharePrice();
        state.vaultBalance = IVault(IStrategy(address(strategy)).vault()).balanceOf(address(this));
        (state.revenueAssets, state.revenueAmounts) = IStrategy(currentStrategy).getRevenue();

        // _printState(state);
        return state;
    }

    function _printState(State memory state) internal pure {
        console.log("state **************************************************");
        console.log("ltv", state.ltv);
        console.log("maxLtv", state.maxLtv);
        console.log("targetLeverage", state.targetLeverage);
        console.log("leverage", state.leverage);
        console.log("total", state.total);
        console.log("collateralAmount", state.collateralAmount);
        console.log("debtAmount", state.debtAmount);
        console.log("targetLeveragePercent", state.targetLeveragePercent);
        console.log("maxLeverage", state.maxLeverage);
        console.log("realTvl", state.realTvl);
        console.log("realSharePrice", state.realSharePrice);
        console.log("vaultBalance", state.vaultBalance);
        console.log("strategyBalanceAsset", state.strategyBalanceAsset);
        console.log("userBalanceAsset", state.userBalanceAsset);
        for (uint i = 0; i < state.revenueAssets.length; i++) {
            console.log("revenueAsset", i, state.revenueAssets[i], state.revenueAmounts[i]);
        }
    }

    function _setMinMaxLtv(uint minLtv, uint maxLtv) internal {
        IFarmingStrategy strategy = IFarmingStrategy(currentStrategy);
        uint farmId = strategy.farmId();
        IFactory factory = IFactory(IPlatform(IControllable(currentStrategy).platform()).factory());

        IFactory.Farm memory farm = factory.farm(farmId);
        farm.nums[0] = minLtv;
        farm.nums[1] = maxLtv;

        vm.prank(platform.multisig());
        factory.updateFarm(farmId, farm);
    }

    function getMinMaxLtv(uint targetLeverage, uint delta) internal pure returns (uint minLtv, uint maxLtv) {
        // a = (-1 + sqrt(1 + delta^2 TL^2)) / delta
        // L0 = TL - a, L1 = TL + a
        // LTVmin = 1 - 1/L0, LTVmax = 1 - 1/L1

        delta = delta * 1e6;
        targetLeverage = targetLeverage * 1e6;
        uint a = uint(
            (-int(1e10 ** 2) + int(FixedPointMathLib.sqrt(1e10 ** 4 + delta * delta * targetLeverage * targetLeverage)))
                / int(delta)
        );
        uint leverage0 = targetLeverage - a;
        uint leverage1 = targetLeverage + a;

        minLtv = 1e4 - 1e4 * 1e10 / leverage0;
        maxLtv = 1e4 - 1e4 * 1e10 / leverage1;
    }

    //endregion --------------------------------------- Internal logic

    //region --------------------------------------- Helper functions
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

    function _setUpFlashLoanVault(address flashLoanVault, ILeverageLendingStrategy.FlashLoanKind kind_) internal {
        _setFlashLoanVault(ILeverageLendingStrategy(currentStrategy), flashLoanVault, uint(kind_));
    }

    function _setFlashLoanVault(ILeverageLendingStrategy strategy, address flashLoanVault, uint kind) internal {
        address multisig = platform.multisig();

        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
        params[10] = kind;
        addresses[0] = flashLoanVault;

        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
    }

    function _getWethPrice8() internal view returns (uint) {
        return IAavePriceOracle(
                IAaveAddressProvider(IPool(PlasmaConstantsLib.AAVE_V3_POOL).ADDRESSES_PROVIDER()).getPriceOracle()
            ).getAssetPrice(PlasmaConstantsLib.TOKEN_WETH);
    }

    function _addRoutes() internal {
        // add routes
        ISwapper swapper = ISwapper(IPlatform(platform).swapper());
        ISwapper.PoolData[] memory pools = new ISwapper.PoolData[](1);
        pools[0] = ISwapper.PoolData({
            pool: PlasmaConstantsLib.TOKEN_WAPLAWETH,
            ammAdapter: (IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.ERC_4626)))).proxy,
            tokenIn: PlasmaConstantsLib.TOKEN_WAPLAWETH,
            tokenOut: PlasmaConstantsLib.TOKEN_WETH
        });
        //        pools[1] = ISwapper.PoolData({
        //            pool: PlasmaConstantsLib.TOKEN_WAPLAUSDE,
        //            ammAdapter: (IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.ERC_4626)))).proxy,
        //            tokenIn: PlasmaConstantsLib.TOKEN_WAPLAUSDE,
        //            tokenOut: PlasmaConstantsLib.TOKEN_USDE
        //        });
        swapper.addPools(pools, false);
    }

    //    function displayAssetsData() internal view {
    //        IAaveDataProvider.TokenData[] memory tokens = IAaveDataProvider(PlasmaConstantsLib.AAVE_V3_POOL_DATA_PROVIDER).getAllReservesTokens();
    //        for (uint i = 0; i < tokens.length; i++) {
    //            IPool.ReserveConfigurationMap memory data = IPool(PlasmaConstantsLib.AAVE_V3_POOL).getReserveData(tokens[i].tokenAddress).configuration;
    //            uint256 eModeCategoryId = (data.data >> 168) & 0xFF;
    //            console.log(tokens[i].symbol, tokens[i].tokenAddress, eModeCategoryId);
    //            console.log(data.data);
    //        }
    //    }

    //endregion --------------------------------------- Helper functions
}
