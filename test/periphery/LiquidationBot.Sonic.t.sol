// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {LiquidationBot} from "../../src/periphery/LiquidationBot.sol";
import {LiquidationBotLib} from "../../src/periphery/libs/LiquidationBotLib.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";

contract LiquidationBotSonicTest is SonicSetup {
    uint internal constant FORK_BLOCK = 45880691; // Sep-05-2025 06:47:56 PM +UTC
    address internal multisig;

    address internal constant STABILITY_USDC_BORROWER = 0x88888887C3ebD4a33E34a15Db4254C74C75E5D4A;

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
        LiquidationBot bot = createLiquidationBotInstance();

        uint balanceUsdcBefore = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(multisig);

        // todo prepare to liquidation

        address[] memory users = new address[](1);
        users[0] = STABILITY_USDC_BORROWER;

        vm.prank(multisig);
        bot.liquidate(SonicConstantsLib.STABILITY_USD_MARKET_POOL, users);

        uint balanceUsdcAfter = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(multisig);

        assertGt(balanceUsdcAfter, balanceUsdcBefore, "get profit in USDC");
    }

    //endregion ----------------------------------- Liquidation Stability USD Market

    //region ----------------------------------- Liquidation Brunch Gen 2 Market
    function testLiquidationBrunchGen2() public {
        LiquidationBot bot = createLiquidationBotInstance();

        // todo

    }

    //endregion ----------------------------------- Liquidation Brunch Gen 2 Market

    //region --------------------------------- Utils
    function createLiquidationBotInstance() internal returns (LiquidationBot) {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new LiquidationBot()));
        LiquidationBot recovery = LiquidationBot(address(proxy));
        recovery.initialize(SonicConstantsLib.PLATFORM);
        return recovery;
    }
    //endregion --------------------------------- Utils

}
