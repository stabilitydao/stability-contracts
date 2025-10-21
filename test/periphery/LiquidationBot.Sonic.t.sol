// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Test.sol";
import {BrunchAdapter} from "../../src/adapters/BrunchAdapter.sol";
import {Aave3PriceOracleMock} from "../../src/test/Aave3PriceOracleMock.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAaveAddressProvider} from "../../src/integrations/aave/IAaveAddressProvider.sol";
import {IAaveDataProvider} from "../../src/integrations/aave/IAaveDataProvider.sol";
import {IAavePoolConfigurator} from "../../src/integrations/aave/IAavePoolConfigurator.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";
import {IAavePriceOracle} from "../../src/integrations/aave/IAavePriceOracle.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {ILiquidationBot} from "../../src/interfaces/ILiquidationBot.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {LiquidationBotLib} from "../../src/periphery/libs/LiquidationBotLib.sol";
import {LiquidationBot} from "../../src/periphery/LiquidationBot.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {AmmAdapterIdLib} from "../../src/adapters/AlgebraV4Adapter.sol";
import {SonicLib} from "../../chains/sonic/SonicLib.sol";
import {console} from "forge-std/console.sol";

contract LiquidationBotSonicTest is SonicSetup {
    uint internal constant FORK_BLOCK = 49491021; // Oct-06-2025 05:58:36 AM +UTC
    address internal multisig;

    address internal constant STABILITY_USDC_BORROWER = 0x88888887C3ebD4a33E34a15Db4254C74C75E5D4A;
    address internal constant STABILITY_POOL = SonicConstantsLib.STABILITY_USD_MARKET_GEN2_POOL;

    address internal constant BRUNCH_USDC_BORROWER = 0x5123525EF2065C01Dd3A24565D6ED560EEA833C1;
    address internal constant BRUNCH_POOL = SonicConstantsLib.BRUNCH_GEN2_POOL;

    uint internal constant ERROR_CODE_HEALTH_FACTOR_NOT_INCREASED = 1;
    uint internal constant ERROR_CODE_NOT_WHITELISTED = 2;

    uint internal constant MAX_GAS = 215_000_000;

    struct SetUpParam {
        address borrower;
        address pool;
        uint targetHealthFactor;
        uint collateralPriceDropPercent;
        address profitTarget;
        address flashLoanVault;
        uint flashLoanKind;
        uint liquidationBonus;
        uint liquidationThreshold;
    }

    struct TestResults {
        ILiquidationBot.UserAccountData stateBefore;
        ILiquidationBot.UserAccountData stateAfter;
        uint expectedCollateralToReceive;
        uint expectedRepayAmount;
        uint repayAmount;
        uint collateralReceived;
        uint gasConsumedByLiquidation;
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();

        _addAdapter();
        _addRoutes();
    }
    //region ----------------------------------- Setup

    function testStorage() public pure {
        bytes32 h =
            keccak256(abi.encode(uint(keccak256("erc7201:stability.LiquidationBot")) - 1)) & ~bytes32(uint(0xff));
        assertEq(h, LiquidationBotLib._LIQUIDATION_BOT_STORAGE_LOCATION, "storage hash");
    }

    //endregion ----------------------------------- Setup

    //region ----------------------------------- Restricted actions
    function testChangeWhitelist() public {
        LiquidationBot recovery = createLiquidationBotInstance();

        address operator1 = makeAddr("operator1");
        address operator2 = makeAddr("operator2");

        assertEq(recovery.whitelisted(multisig), true, "multisig is whitelisted by default");
        assertEq(recovery.whitelisted(operator1), false, "operator1 is not whitelisted by default");
        assertEq(recovery.whitelisted(operator2), false, "operator2 is not whitelisted by default");

        vm.expectRevert(IControllable.NotOperator.selector);
        vm.prank(address(this));
        recovery.changeWhitelist(operator1, true);

        vm.prank(multisig);
        recovery.changeWhitelist(operator1, true);

        assertEq(recovery.whitelisted(operator1), true, "operator1 is whitelisted");
        assertEq(recovery.whitelisted(operator2), false, "operator2 is not whitelisted");

        vm.prank(multisig);
        recovery.changeWhitelist(operator2, true);

        assertEq(recovery.whitelisted(operator2), true, "operator2 is whitelisted");

        vm.prank(multisig);
        recovery.changeWhitelist(operator1, false);

        assertEq(recovery.whitelisted(operator1), false, "operator1 is not whitelisted");
        assertEq(recovery.whitelisted(operator2), true, "operator2 is whitelisted");
    }

    function testPriceImpactTolerance() public {
        LiquidationBot bot = createLiquidationBotInstance();

        uint defaultTolerance = bot.priceImpactTolerance();
        assertEq(defaultTolerance, LiquidationBotLib.DEFAULT_SWAP_PRICE_IMPACT_TOLERANCE, "expected default tolerance");

        vm.expectRevert(IControllable.NotOperator.selector);
        vm.prank(address(this));
        bot.setPriceImpactTolerance(5_000);

        vm.prank(multisig);
        bot.setPriceImpactTolerance(5_000);

        uint newTolerance = bot.priceImpactTolerance();
        assertEq(newTolerance, 5_000, "new tolerance is 5%");

        vm.prank(multisig);
        bot.setPriceImpactTolerance(0);

        assertEq(
            defaultTolerance, LiquidationBotLib.DEFAULT_SWAP_PRICE_IMPACT_TOLERANCE, "default tolerance is restored"
        );
    }

    function testSetProfitTarget() public {
        LiquidationBot bot = createLiquidationBotInstance();

        address defaultTarget = bot.profitTarget();
        assertEq(defaultTarget, address(0), "expected default target");

        address target1 = makeAddr("target1");
        address target2 = makeAddr("target2");

        vm.expectRevert(IControllable.NotMultisig.selector);
        vm.prank(address(this));
        bot.setProfitTarget(target1);

        vm.prank(multisig);
        bot.setProfitTarget(target1);

        address newTarget = bot.profitTarget();
        assertEq(newTarget, target1, "new target is set");

        vm.prank(multisig);
        bot.setProfitTarget(target2);

        newTarget = bot.profitTarget();
        assertEq(newTarget, target2, "new target is updated");

        vm.prank(multisig);
        bot.setProfitTarget(address(0));

        newTarget = bot.profitTarget();
        assertEq(newTarget, address(0), "default target is restored");
    }

    function testSetFlashLoanVault() public {
        LiquidationBot bot = createLiquidationBotInstance();

        (address defaultVault, uint defaultKind) = bot.getFlashLoanVault();
        assertEq(defaultVault, address(0), "expected default vault");
        assertEq(defaultKind, 0, "expected default kind");

        address vault1 = makeAddr("vault1");
        address vault2 = makeAddr("vault2");
        uint kind1 = uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1);
        uint kind2 = uint(ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3);

        vm.expectRevert(IControllable.NotOperator.selector);
        vm.prank(address(this));
        bot.setFlashLoanVault(vault1, kind1);

        vm.prank(multisig);
        bot.setFlashLoanVault(vault1, kind1);

        (address newVault, uint newKind) = bot.getFlashLoanVault();
        assertEq(newVault, vault1, "new vault is set");
        assertEq(newKind, kind1, "new kind is set");

        vm.prank(multisig);
        bot.setFlashLoanVault(vault2, kind2);

        (newVault, newKind) = bot.getFlashLoanVault();
        assertEq(newVault, vault2, "new vault is updated");
        assertEq(newKind, kind2, "new kind is updated");

        vm.prank(multisig);
        bot.setFlashLoanVault(address(0), 0);

        (newVault, newKind) = bot.getFlashLoanVault();
        assertEq(newVault, address(0), "default (empty) vault is restored");
        assertEq(newKind, 0, "default kind is restored");
    }

    function testChangeWrappedMetaVault() public {
        LiquidationBot bot = createLiquidationBotInstance();

        assertEq(
            bot.isWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD), false, "not registered by default"
        );
        assertEq(bot.isWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAS), false, "not registered by default");

        vm.expectRevert(IControllable.NotOperator.selector);
        vm.prank(address(this));
        bot.changeWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, true);

        vm.prank(multisig);
        bot.changeWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, true);

        assertEq(bot.isWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD), true, "registered now");
        assertEq(bot.isWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAS), false, "not registered by default");

        vm.prank(multisig);
        bot.changeWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, false);

        vm.prank(multisig);
        bot.changeWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAS, true);

        assertEq(bot.isWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD), false, "not registered again");
        assertEq(bot.isWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAS), true, "registered");
    }

    function testSetTargetHealthFactor() public {
        LiquidationBot bot = createLiquidationBotInstance();

        assertEq(bot.targetHealthFactor(), 0, "default target HF is 0 (max repay)");

        vm.expectRevert(IControllable.NotOperator.selector);
        vm.prank(address(this));
        bot.setTargetHealthFactor(1.01e18);

        vm.prank(multisig);
        bot.setTargetHealthFactor(1.01e18);

        assertEq(bot.targetHealthFactor(), 1.01e18, "1.01");

        //        vm.expectRevert(LiquidationBotLib.InvalidHealthFactor.selector);
        //        vm.prank(multisig);
        //        bot.setTargetHealthFactor(0.99e18);

        assertEq(bot.targetHealthFactor(), 1.01e18, "1.01");

        vm.prank(multisig);
        bot.setTargetHealthFactor(0);

        assertEq(bot.targetHealthFactor(), 0, "default target HF is 0 again (max repay)");
    }

    //endregion ----------------------------------- Restricted actions

    //region ----------------------------------- Liquidation Stability USD Market - various flash loans, multisig
    function testLiquidationStabilityUsdcFlashBalancerV31() public {
        _testLiquidationStabilitySuccess(
            SetUpParam({
                borrower: STABILITY_USDC_BORROWER,
                pool: STABILITY_POOL,
                targetHealthFactor: 1.001e18,
                collateralPriceDropPercent: 2, // drop collateral price by 2%
                profitTarget: multisig,
                flashLoanVault: SonicConstantsLib.BEETS_VAULT_V3,
                flashLoanKind: uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1),
                liquidationBonus: 10010, // 0.1% bonus
                liquidationThreshold: 0
            }),
            SonicConstantsLib.TOKEN_USDC,
            multisig
        );
    }

    function testLiquidationStabilityUsdcFlashBalancerV2() public {
        _testLiquidationStabilitySuccess(
            SetUpParam({
                borrower: STABILITY_USDC_BORROWER,
                pool: STABILITY_POOL,
                targetHealthFactor: 1.001e18,
                collateralPriceDropPercent: 2, // drop collateral price by 2%
                profitTarget: multisig,
                flashLoanVault: SonicConstantsLib.BEETS_VAULT,
                flashLoanKind: uint(ILeverageLendingStrategy.FlashLoanKind.Default_0),
                liquidationBonus: 10010, // 0.1% bonus
                liquidationThreshold: 0
            }),
            SonicConstantsLib.TOKEN_USDC,
            multisig
        );
    }

    function testLiquidationStabilityUsdcFlashUniswapV3() public {
        _testLiquidationStabilitySuccess(
            SetUpParam({
                borrower: STABILITY_USDC_BORROWER,
                pool: STABILITY_POOL,
                targetHealthFactor: 1.001e18,
                collateralPriceDropPercent: 2, // drop collateral price by 2%
                profitTarget: multisig,
                flashLoanVault: SonicConstantsLib.POOL_SHADOW_CL_USDC_USDT,
                flashLoanKind: uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2),
                liquidationBonus: 10010, // 0.1% bonus
                liquidationThreshold: 0
            }),
            SonicConstantsLib.TOKEN_USDC,
            multisig
        );
    }

    function testLiquidationStabilityUsdcFlashAlgebraV4() public {
        _testLiquidationStabilitySuccess(
            SetUpParam({
                borrower: STABILITY_USDC_BORROWER,
                pool: STABILITY_POOL,
                targetHealthFactor: 1.001e18,
                collateralPriceDropPercent: 2, // drop collateral price by 2%
                profitTarget: multisig,
                flashLoanVault: SonicConstantsLib.POOL_ALGEBRA_WS_USDC,
                flashLoanKind: uint(ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3),
                liquidationBonus: 10010, // 0.1% bonus
                liquidationThreshold: 0
            }),
            SonicConstantsLib.TOKEN_USDC,
            multisig
        );
    }

    //endregion ----------------------------------- Liquidation Stability USD Market - various flash loans, multisig

    //region ----------------------------------- Liquidation Stability USD Market - good paths, whitelisted
    function testLiquidationStabilityUsdcWhitelisted() public {
        _testLiquidationStabilitySuccess(
            SetUpParam({
                borrower: STABILITY_USDC_BORROWER,
                pool: STABILITY_POOL,
                targetHealthFactor: 1.001e18,
                collateralPriceDropPercent: 2,
                profitTarget: multisig,
                flashLoanVault: SonicConstantsLib.BEETS_VAULT_V3,
                flashLoanKind: uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1),
                liquidationBonus: 10040, // 0.1% bonus
                liquidationThreshold: 0
            }),
            SonicConstantsLib.TOKEN_USDC,
            address(this)
        );
    }

    function testLiquidationStabilityUsdcZeroTargetHealthFactor() public {
        _testLiquidationStabilitySuccess(
            SetUpParam({
                borrower: STABILITY_USDC_BORROWER,
                pool: STABILITY_POOL,
                targetHealthFactor: 0, // (!)
                collateralPriceDropPercent: 2,
                profitTarget: multisig,
                flashLoanVault: SonicConstantsLib.BEETS_VAULT_V3,
                flashLoanKind: uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1),
                liquidationBonus: 10010,
                liquidationThreshold: 0
            }),
            SonicConstantsLib.TOKEN_USDC,
            multisig
        );
    }

    function testLiquidationStabilityUsdcHighBonus() public {
        ILiquidationBot bot = createLiquidationBotInstance();

        SetUpParam memory stParams = SetUpParam({
            borrower: STABILITY_USDC_BORROWER,
            pool: STABILITY_POOL,
            targetHealthFactor: 1.001e18,
            collateralPriceDropPercent: 2, // drop collateral price by 2%
            profitTarget: multisig,
            flashLoanVault: SonicConstantsLib.BEETS_VAULT_V3,
            flashLoanKind: uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1),
            liquidationBonus: 10100, // (!)
            liquidationThreshold: 0
        });
        _setUpStabilityMarket(stParams, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);

        uint profit0 = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(stParams.profitTarget);
        TestResults memory ret = _testLiquidation(bot, stParams, 0, address(this), true);
        uint profit1 = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(stParams.profitTarget);

        assertGt(profit1, profit0, "get positive profit");

        assertLt(ret.stateBefore.healthFactor, 1e18, "liquidation was actually required");
        assertLt(ret.stateAfter.healthFactor, 1e18, "liquidation is still required"); // (!)
        assertGt(ret.stateAfter.healthFactor, ret.stateBefore.healthFactor, "Health factor is increased"); // (!)

        assertEq(ret.repayAmount, ret.expectedRepayAmount, "repay amount is as expected");
        assertApproxEqRel(
            ret.collateralReceived, ret.expectedCollateralToReceive, 1e18 / 1e6, "collateral received is as expected"
        );

        assertLt(ret.gasConsumedByLiquidation, MAX_GAS, "gas used is reasonable");
    }

    function testLiquidationStabilityUsdcHighTargetHealthFactor() public {
        ILiquidationBot bot = createLiquidationBotInstance();

        SetUpParam memory stParams = SetUpParam({
            borrower: STABILITY_USDC_BORROWER,
            pool: STABILITY_POOL,
            targetHealthFactor: 2.0e18, // (!) very high value
            collateralPriceDropPercent: 2, // drop collateral price by 2%
            profitTarget: multisig,
            flashLoanVault: SonicConstantsLib.BEETS_VAULT_V3,
            flashLoanKind: uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1),
            liquidationBonus: 10010,
            liquidationThreshold: 0
        });
        _setUpStabilityMarket(stParams, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);

        TestResults memory ret = _testLiquidation(bot, stParams, 0, address(this), true);

        assertLt(ret.stateBefore.healthFactor, 1e18, "liquidation was actually required");
        assertGt(ret.stateAfter.healthFactor, 1e18, "liquidation is not required");
        assertLt(ret.stateAfter.healthFactor, 1.1e18, "but target HF is not reached");
    }

    function testLiquidationStabilityUsdcNoLiquidationRequired() public {
        ILiquidationBot bot = createLiquidationBotInstance();

        SetUpParam memory stParams = SetUpParam({
            borrower: STABILITY_USDC_BORROWER,
            pool: STABILITY_POOL,
            targetHealthFactor: 1.001e18,
            collateralPriceDropPercent: 0,
            profitTarget: multisig,
            flashLoanVault: SonicConstantsLib.BEETS_VAULT_V3,
            flashLoanKind: uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1),
            liquidationBonus: 10100,
            liquidationThreshold: 0
        });
        _setUpStabilityMarket(stParams, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);

        TestResults memory ret = _testLiquidation(bot, stParams, 0, address(this), false);

        assertEq(
            ret.stateAfter.healthFactor,
            ret.stateBefore.healthFactor,
            "Health factor is not changed, user was just skipped"
        );
        assertEq(ret.stateAfter.totalDebtBase, ret.stateBefore.totalDebtBase, "totalDebtBase is not changed");
        assertEq(
            ret.stateAfter.totalCollateralBase,
            ret.stateBefore.totalCollateralBase,
            "totalCollateralBase is not changed"
        );
        assertEq(
            ret.stateAfter.availableBorrowsBase,
            ret.stateBefore.availableBorrowsBase,
            "availableBorrowsBase is not changed"
        );
    }

    //endregion ----------------------------------- Liquidation Stability USD Market - good paths, whitelisted

    //region ----------------------------------- Liquidation Stability USD Market - bad paths
    function testLiquidationStabilityUsdcHealthFactorDecreased() public {
        LiquidationBot bot = createLiquidationBotInstance();

        SetUpParam memory stParams = SetUpParam({
            borrower: STABILITY_USDC_BORROWER,
            pool: STABILITY_POOL,
            targetHealthFactor: 1.001e18,
            collateralPriceDropPercent: 25, // (!)
            profitTarget: multisig,
            flashLoanVault: SonicConstantsLib.BEETS_VAULT_V3,
            flashLoanKind: uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1),
            liquidationBonus: 10150, // (!)
            liquidationThreshold: 0
        });

        _setUpStabilityMarket(stParams, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);

        uint profit0 = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(stParams.profitTarget);
        TestResults memory ret = _testLiquidation(bot, stParams, 0, multisig, true);
        uint profit1 = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(stParams.profitTarget);

        assertLt(ret.stateAfter.healthFactor, ret.stateBefore.healthFactor, "Health factor is decreased");
        assertGt(profit1, profit0, "get positive profit 1");

        TestResults memory ret2 = _testLiquidation(bot, stParams, 0, multisig, false);
        uint profit2 = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(stParams.profitTarget);

        assertLt(ret2.stateAfter.healthFactor, ret.stateBefore.healthFactor, "Health factor is decreased more");
        assertGt(profit2, profit1, "get positive profit 2");
    }

    function testLiquidationStabilityUsdcNotWhitelisted() public {
        _testLiquidationStabilityFail(
            SetUpParam({
                borrower: STABILITY_USDC_BORROWER,
                pool: STABILITY_POOL,
                targetHealthFactor: 1.001e18,
                collateralPriceDropPercent: 3,
                profitTarget: multisig,
                flashLoanVault: SonicConstantsLib.BEETS_VAULT_V3,
                flashLoanKind: uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1),
                liquidationBonus: 10010, // 0.1% bonus
                liquidationThreshold: 0
            }),
            ERROR_CODE_NOT_WHITELISTED
        );
    }

    //endregion ----------------------------------- Liquidation Stability USD Market - bad paths

    //region ----------------------------------- Liquidation Brunch Gen 2 Market
    function testLiquidationBrunchGen2() public {
        LiquidationBot bot = createLiquidationBotInstance();

        address profitToken = SonicConstantsLib.TOKEN_USDC;

        vm.prank(multisig);
        bot.setPriceImpactTolerance(5_000);

        SetUpParam memory stParams = SetUpParam({
            borrower: BRUNCH_USDC_BORROWER,
            pool: BRUNCH_POOL,
            targetHealthFactor: 1.001e18,
            collateralPriceDropPercent: 1,
            profitTarget: multisig,
            flashLoanVault: SonicConstantsLib.POOL_UNISWAPV3_USDC_WETH_500,
            flashLoanKind: uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2),
            liquidationBonus: 10300,
            liquidationThreshold: 9500
        });

        _setUpStabilityMarket(stParams, SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD);

        uint profit0 = IERC20(profitToken).balanceOf(stParams.profitTarget);
        TestResults memory ret = _testLiquidation(bot, stParams, 0, address(this), true);
        uint profit1 = IERC20(profitToken).balanceOf(stParams.profitTarget);

        assertGt(profit1, profit0, "get positive profit");

        assertLt(ret.stateBefore.healthFactor, 1e18, "liquidation was actually required");
        assertGt(ret.stateAfter.healthFactor, 1e18, "liquidation is not required anymore");

        assertEq(ret.repayAmount, ret.expectedRepayAmount, "repay amount is as expected");
        assertApproxEqRel(
            ret.collateralReceived, ret.expectedCollateralToReceive, 1e18 / 1e6, "collateral received is as expected"
        );

        assertLt(ret.gasConsumedByLiquidation, MAX_GAS, "gas used is reasonable");
    }

    function testLiquidationBrunchStudySetupMarketParams() internal {
        uint[1] memory liquidationThresholds = [uint(9500)];
        uint[8] memory bonuses = [10350, 10250, 10200, uint(10150), 10110, 10070, 10030, 10010];

        for (uint i; i < liquidationThresholds.length; ++i) {
            for (uint j; j < bonuses.length; ++j) {
                uint snapshot = vm.snapshotState();
                SetUpParam memory stParams = SetUpParam({
                    borrower: BRUNCH_USDC_BORROWER,
                    pool: BRUNCH_POOL,
                    targetHealthFactor: 1.001e18,
                    collateralPriceDropPercent: 1,
                    profitTarget: multisig,
                    flashLoanVault: SonicConstantsLib.POOL_UNISWAPV3_USDC_WETH_500,
                    flashLoanKind: uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2),
                    liquidationBonus: bonuses[j],
                    liquidationThreshold: liquidationThresholds[i]
                });
                (TestResults memory ret, uint profit) =
                    _testLiquidationBrunchGen2SetupMarketParams(stParams, SonicConstantsLib.TOKEN_USDC);
                console.log(
                    liquidationThresholds[i],
                    bonuses[j],
                    profit,
                    (ret.stateBefore.healthFactor < ret.stateAfter.healthFactor) && (ret.stateAfter.healthFactor > 1)
                );
                vm.revertToState(snapshot);
            }
        }
    }

    //endregion ----------------------------------- Liquidation Brunch Gen 2 Market

    //region --------------------------------- Tests implementation
    function _testLiquidationBrunchGen2SetupMarketParams(
        SetUpParam memory stParams,
        address profitToken
    ) internal returns (TestResults memory ret, uint profit) {
        LiquidationBot bot = createLiquidationBotInstance();

        vm.prank(multisig);
        bot.setPriceImpactTolerance(5_000);

        _setUpStabilityMarket(stParams, SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD);

        uint profit0 = IERC20(profitToken).balanceOf(stParams.profitTarget);
        ret = _testLiquidation(bot, stParams, type(uint).max, address(this), true);
        uint profit1 = IERC20(profitToken).balanceOf(stParams.profitTarget);

        return (ret, profit1 - profit0);
    }

    function _testLiquidationStabilitySuccess(
        SetUpParam memory stParams_,
        address profitToken,
        address caller
    ) internal {
        LiquidationBot bot = createLiquidationBotInstance();
        _setUpStabilityMarket(stParams_, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);

        uint profit0 = IERC20(profitToken).balanceOf(stParams_.profitTarget);
        TestResults memory ret = _testLiquidation(bot, stParams_, 0, caller, true);
        uint profit1 = IERC20(profitToken).balanceOf(stParams_.profitTarget);

        assertGt(profit1, profit0, "get positive profit");

        assertLt(ret.stateBefore.healthFactor, 1e18, "liquidation was actually required");
        assertGt(ret.stateAfter.healthFactor, 1e18, "liquidation is not required anymore");

        assertEq(ret.repayAmount, ret.expectedRepayAmount, "repay amount is as expected");
        assertApproxEqRel(
            ret.collateralReceived, ret.expectedCollateralToReceive, 1e18 / 1e6, "collateral received is as expected"
        );

        assertLt(ret.gasConsumedByLiquidation, MAX_GAS, "gas used is reasonable");
    }

    function _testLiquidationStabilityFail(SetUpParam memory stParams_, uint errorCode) internal {
        LiquidationBot bot = createLiquidationBotInstance();
        _setUpStabilityMarket(stParams_, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);

        address caller = errorCode == ERROR_CODE_NOT_WHITELISTED ? makeAddr("random") : multisig;
        _testLiquidation(bot, stParams_, errorCode, caller, true);
    }

    //endregion --------------------------------- Tests implementation

    //region --------------------------------- Internal logic
    function _testLiquidation(
        ILiquidationBot bot,
        SetUpParam memory stParams_,
        uint errorCode,
        address caller,
        bool reducePrices_
    ) internal returns (TestResults memory ret) {
        // ------------------------------ set up bot
        vm.prank(multisig);
        bot.changeWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, true);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSD).changeWhitelist(address(bot), true);

        vm.prank(multisig);
        bot.setTargetHealthFactor(stParams_.targetHealthFactor);

        vm.prank(multisig);
        bot.setProfitTarget(stParams_.profitTarget);

        vm.prank(multisig);
        bot.setFlashLoanVault(stParams_.flashLoanVault, stParams_.flashLoanKind);

        // whitelist this, not caller because in bad-paths caller can be different from address(this)
        vm.prank(multisig);
        bot.changeWhitelist(address(this), true);

        // ------------------------------ prepare to liquidation
        // check user health factor
        if (reducePrices_) {
            {
                ILiquidationBot.UserAccountData memory state0 =
                    bot.getUserAccountData(stParams_.pool, stParams_.borrower);
                assertGt(state0.healthFactor, 1e18, "no liquidation needed");
            }

            {
                IAaveAddressProvider addressProvider = IAaveAddressProvider(IPool(stParams_.pool).ADDRESSES_PROVIDER());

                // get AAVE oracle, get current prices for both assets - collateral and borrow
                IAavePriceOracle oracle = IAavePriceOracle(addressProvider.getPriceOracle());

                // replace AAVE oracle with mock oracle
                ILiquidationBot.UserAssetInfo[] memory assets = bot.getUserAssetInfo(stParams_.pool, stParams_.borrower);
                assertEq(assets.length, 2, "expected 2 assets");

                uint collateralIndex = assets[0].currentATokenBalance == 0 ? 1 : 0;
                uint borrowIndex = assets[0].currentATokenBalance == 0 ? 0 : 1;

                // set mock prices to make user undercollateralized
                {
                    uint priceCollateral = oracle.getAssetPrice(assets[collateralIndex].asset);

                    Aave3PriceOracleMock mockOracle = new Aave3PriceOracleMock(address(oracle));
                    mockOracle.setAssetPrice(
                        assets[collateralIndex].asset,
                        priceCollateral * (100 - stParams_.collateralPriceDropPercent) / 100
                    );

                    vm.prank(addressProvider.owner());
                    addressProvider.setPriceOracle(address(mockOracle));
                }

                // check user health factor
                ret.stateBefore = bot.getUserAccountData(stParams_.pool, stParams_.borrower);

                ret.expectedRepayAmount = bot.getRepayAmount(
                    stParams_.pool,
                    assets[collateralIndex].asset,
                    assets[borrowIndex].asset,
                    ret.stateBefore,
                    stParams_.targetHealthFactor
                );

                ret.expectedCollateralToReceive = bot.getCollateralToReceive(
                    stParams_.pool,
                    assets[collateralIndex].asset,
                    assets[borrowIndex].asset,
                    assets[collateralIndex].currentATokenBalance,
                    ret.expectedRepayAmount
                );
            }
        } else {
            ret.stateBefore = bot.getUserAccountData(stParams_.pool, stParams_.borrower);
        }

        // ------------------------------ liquidation
        address[] memory users = new address[](1);
        users[0] = stParams_.borrower;

        {
            vm.recordLogs();

            uint gasBefore = gasleft();

            if (errorCode == 0) {
                vm.prank(caller);
                bot.liquidate(stParams_.pool, users, type(uint).max);
            } else {
                vm.prank(caller);
                try bot.liquidate(stParams_.pool, users, type(uint).max) {
                    require(errorCode == type(uint).max, "_testLiquidation: operation was expected to fail");
                } catch (bytes memory reason) {
                    if (errorCode == ERROR_CODE_HEALTH_FACTOR_NOT_INCREASED) {
                        require(
                            reason.length >= 4 && bytes4(reason) == LiquidationBotLib.HealthFactorNotIncreased.selector,
                            "Some other error was thrown instead of HealthFactorNotIncreased"
                        );
                    } else if (errorCode == ERROR_CODE_NOT_WHITELISTED) {
                        require(
                            reason.length >= 4 && bytes4(reason) == LiquidationBotLib.NotWhitelisted.selector,
                            "Some other error was thrown instead of NotOperator"
                        );
                    } else if (errorCode == type(uint).max) {
                        // any error is accepted
                    } else {
                        require(false, "_testLiquidation: unknown error");
                    }
                }
            }

            ret.gasConsumedByLiquidation = gasBefore - gasleft();

            Vm.Log[] memory logs = vm.getRecordedLogs();

            bytes32 eventSignature = keccak256("OnLiquidation(address,address,uint256,uint256)");
            for (uint i = 0; i < logs.length; i++) {
                if (logs[i].topics[0] == eventSignature) {
                    (,, ret.repayAmount, ret.collateralReceived) =
                        abi.decode(logs[i].data, (address, address, uint, uint));
                    break;
                }
            }
        }

        ret.stateAfter = bot.getUserAccountData(stParams_.pool, stParams_.borrower);

        return ret;
    }

    function _setUpStabilityMarket(SetUpParam memory stParams_, address collateralAsset) internal {
        address owner = IAaveAddressProvider(IPool(stParams_.pool).ADDRESSES_PROVIDER()).owner();
        IAavePoolConfigurator configurator = IAavePoolConfigurator(
            IAaveAddressProvider(IPool(stParams_.pool).ADDRESSES_PROVIDER()).getPoolConfigurator()
        );

        vm.prank(owner);
        configurator.setLiquidationProtocolFee(collateralAsset, 1);

        (, uint ltv, uint liquidationThreshold, uint liquidationBonus,,,,,,) = IAaveDataProvider(
                IAaveAddressProvider(IPool(stParams_.pool).ADDRESSES_PROVIDER()).getPoolDataProvider()
            ).getReserveConfigurationData(collateralAsset);

        uint newLiquidationThreshold =
            stParams_.liquidationThreshold == 0 ? liquidationThreshold : stParams_.liquidationThreshold;
        uint newBonus = stParams_.liquidationBonus == 0 ? liquidationBonus : stParams_.liquidationBonus;

        // console.log("Set liquidation params:", newLiquidationThreshold, newBonus);
        vm.prank(owner);
        configurator.configureReserveAsCollateral(collateralAsset, ltv, newLiquidationThreshold, newBonus);
    }

    //endregion --------------------------------- Internal logic

    //region --------------------------------- Utils
    function createLiquidationBotInstance() internal returns (LiquidationBot) {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new LiquidationBot()));

        LiquidationBot bot = LiquidationBot(address(proxy));
        bot.initialize(SonicConstantsLib.PLATFORM);

        return bot;
    }

    function showState(ILiquidationBot.UserAccountData memory state_) internal pure {
        console.log("state:");
        console.log("  totalCollateralBase", state_.totalCollateralBase);
        console.log("  totalDebtBase", state_.totalDebtBase);
        console.log("  availableBorrowsBase", state_.availableBorrowsBase);
        console.log("  currentLiquidationThreshold", state_.currentLiquidationThreshold);
        console.log("  ltv", state_.ltv);
        console.log("  healthFactor", state_.healthFactor);
    }

    function _addAdapter() internal returns (BrunchAdapter adapter) {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BrunchAdapter()));
        BrunchAdapter(address(proxy)).init(SonicConstantsLib.PLATFORM);
        multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();

        //        IPriceReader priceReader = IPriceReader(IPlatform(SonicConstantsLib.PLATFORM).priceReader());
        //        vm.prank(multisig);
        //        priceReader.addAdapter(address(proxy));  // ! AMM adapters are NOT added to price reader, only oracle adapters are add

        adapter = BrunchAdapter(address(proxy));

        vm.prank(multisig);
        IPlatform(SonicConstantsLib.PLATFORM).addAmmAdapter(AmmAdapterIdLib.BRUNCH, address(proxy));
    }

    function _addRoutes() internal {
        ISwapper swapper = ISwapper(IPlatform(SonicConstantsLib.PLATFORM).swapper());

        ISwapper.AddPoolData[] memory pools = new ISwapper.AddPoolData[](2);
        pools[0] = SonicLib._makePoolData(
            SonicConstantsLib.POOL_SHADOW_USDC_BRUNCH_USDC,
            AmmAdapterIdLib.SOLIDLY,
            SonicConstantsLib.TOKEN_BRUNCH_USD,
            SonicConstantsLib.TOKEN_USDC
        );
        pools[1] = SonicLib._makePoolData(
            SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD,
            AmmAdapterIdLib.BRUNCH,
            SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD,
            SonicConstantsLib.TOKEN_BRUNCH_USD
        );

        vm.prank(multisig);
        swapper.addPools(pools, false);
    }
    //endregion --------------------------------- Utils
}
