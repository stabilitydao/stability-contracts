// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Aave3PriceOracleMock} from "../../src/test/Aave3PriceOracleMock.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAaveAddressProvider} from "../../src/integrations/aave/IAaveAddressProvider.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";
import {IAavePriceOracle} from "../../src/integrations/aave/IAavePriceOracle.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {ILiquidationBot} from "../../src/interfaces/ILiquidationBot.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {LiquidationBotLib} from "../../src/periphery/libs/LiquidationBotLib.sol";
import {LiquidationBot} from "../../src/periphery/LiquidationBot.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {console} from "forge-std/console.sol";

contract LiquidationBotSonicTest is SonicSetup {
    uint internal constant FORK_BLOCK = 49491021; // Oct-06-2025 05:58:36 AM +UTC
    address internal multisig;

    address internal constant STABILITY_USDC_BORROWER = 0x88888887C3ebD4a33E34a15Db4254C74C75E5D4A;
    address internal constant STABILITY_POOL = SonicConstantsLib.STABILITY_USD_MARKET_GEN2_POOL;

    struct SetUpParam {
        address borrower;
        address pool;
        uint targetHealthFactor;
        uint collateralPriceDropPercent;
        address profitTarget;
        address flashLoanVault;
        uint flashLoanKind;
        uint allowedGas;
    }

    constructor() {
        vm.rollFork(FORK_BLOCK);
        multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();
    }

    //region ----------------------------------- Restricted actions
    function testChangeWhitelist() public {
        LiquidationBot recovery = createLiquidationBotInstance();

        address operator1 = makeAddr("operator1");
        address operator2 = makeAddr("operator2");

        assertEq(recovery.whitelisted(multisig), true, "multisig is whitelisted by default");
        assertEq(recovery.whitelisted(operator1), false, "operator1 is not whitelisted by default");
        assertEq(recovery.whitelisted(operator2), false, "operator2 is not whitelisted by default");

        vm.expectRevert(IControllable.NotMultisig.selector);
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

        vm.expectRevert(IControllable.NotMultisig.selector);
        vm.prank(address(this));
        bot.setPriceImpactTolerance(5_000);

        vm.prank(multisig);
        bot.setPriceImpactTolerance(5_000);

        uint newTolerance = bot.priceImpactTolerance();
        assertEq(newTolerance, 5_000, "new tolerance is 5%");

        vm.prank(multisig);
        bot.setPriceImpactTolerance(0);

        assertEq(defaultTolerance, LiquidationBotLib.DEFAULT_SWAP_PRICE_IMPACT_TOLERANCE, "default tolerance is restored");
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

        vm.expectRevert(IControllable.NotMultisig.selector);
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

    //endregion ----------------------------------- Restricted actions

    //region ----------------------------------- Liquidation Stability USD Market
    function testLiquidationStabilityUsdc() public {
        uint balanceUsdcBefore = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(multisig);
        (
            ILiquidationBot.UserAccountData memory stateBefore,
            ILiquidationBot.UserAccountData memory stateAfter
        ) = _testLiquidationStabilityUsdc(SetUpParam({
            borrower: STABILITY_USDC_BORROWER,
            pool: STABILITY_POOL,
            targetHealthFactor: 1e18 + 1e16, // 1.01
            collateralPriceDropPercent: 2, // drop collateral price by 5%
            profitTarget: multisig,
            flashLoanVault: SonicConstantsLib.BEETS_VAULT_V3,
            flashLoanKind: uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1),
            allowedGas: 15_000_000
        }));
        uint balanceUsdcAfter = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(multisig);

        assertGt(balanceUsdcAfter, balanceUsdcBefore, "get profit in USDC");
        console.log("profit", balanceUsdcAfter - balanceUsdcBefore);

        showState(stateBefore);
        showState(stateAfter);

        assertLt(stateBefore.healthFactor, 1e18, "liquidation is required");
        assertGt(stateAfter.healthFactor, 1e18, "liquidation is not required anymore");

    }

    //endregion ----------------------------------- Liquidation Stability USD Market

    //region ----------------------------------- Liquidation Brunch Gen 2 Market
    function testLiquidationBrunchGen2() public {
        LiquidationBot bot = createLiquidationBotInstance();

        // todo

    }

    //endregion ----------------------------------- Liquidation Brunch Gen 2 Market


    //region --------------------------------- Tests implementation
    function _testLiquidationStabilityUsdc(SetUpParam memory stParams_) internal returns (
        ILiquidationBot.UserAccountData memory stateBefore,
        ILiquidationBot.UserAccountData memory stateAfter
    ) {
        LiquidationBot bot = createLiquidationBotInstance();

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


        // ------------------------------ prepare to liquidation
        // check user health factor
        {
            ILiquidationBot.UserAccountData memory state0 = bot.getUserAccountData(stParams_.pool, stParams_.borrower);
            assertGt(state0.healthFactor, 1e18, "no liquidation needed");
        }

        {
            IAaveAddressProvider addressProvider = IAaveAddressProvider(
                IPool(STABILITY_POOL).ADDRESSES_PROVIDER()
            );

            // get AAVE oracle, get current prices for both assets - collateral and borrow
            IAavePriceOracle oracle = IAavePriceOracle(addressProvider.getPriceOracle());

            // replace AAVE oracle with mock oracle
            ILiquidationBot.UserAssetInfo[] memory assets = bot.getUserAssetInfo(stParams_.pool, stParams_.borrower);
            assertEq(assets.length, 2, "expected 2 assets");

            address collateralAsset = assets[0].currentATokenBalance != 0 ? assets[0].asset : assets[1].asset;

            uint priceCollateral = oracle.getAssetPrice(collateralAsset);

            // set mock prices to make user undercollateralized
            Aave3PriceOracleMock mockOracle = new Aave3PriceOracleMock(address(oracle));
            mockOracle.setAssetPrice(collateralAsset, priceCollateral * (100 - stParams_.collateralPriceDropPercent) / 100);

            vm.prank(addressProvider.owner());
            addressProvider.setPriceOracle(address(mockOracle));
        }

        // check user health factor
        stateBefore = bot.getUserAccountData(stParams_.pool, stParams_.borrower);

        // ------------------------------ liquidation
        address[] memory users = new address[](1);
        users[0] = stParams_.borrower;

        {
            uint gasBefore = gasleft();
            vm.prank(multisig);
            bot.liquidate(stParams_.pool, users);
            uint gasAfter = gasleft();
            assertLt(gasBefore - gasAfter, stParams_.allowedGas, "gas used is reasonable");
        }

        stateAfter = bot.getUserAccountData(stParams_.pool, stParams_.borrower);
    }

    //endregion --------------------------------- Tests implementation

    //region --------------------------------- Utils
    function createLiquidationBotInstance() internal returns (LiquidationBot) {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new LiquidationBot()));

        LiquidationBot bot = LiquidationBot(address(proxy));
        bot.initialize(SonicConstantsLib.PLATFORM);

        return bot;
    }

    function showState(ILiquidationBot.UserAccountData memory state_) internal view {
        console.log("state:");
        console.log("  totalCollateralBase", state_.totalCollateralBase);
        console.log("  totalDebtBase", state_.totalDebtBase);
        console.log("  availableBorrowsBase", state_.availableBorrowsBase);
        console.log("  currentLiquidationThreshold", state_.currentLiquidationThreshold);
        console.log("  ltv", state_.ltv);
        console.log("  healthFactor", state_.healthFactor);
    }
    //endregion --------------------------------- Utils

}
