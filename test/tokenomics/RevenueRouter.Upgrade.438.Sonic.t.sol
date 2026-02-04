// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {XStaking, IXStaking} from "../../src/tokenomics/XStaking.sol";
import {XToken} from "../../src/tokenomics/XToken.sol";
import {IXToken} from "../../src/interfaces/IXToken.sol";
import {Platform} from "../../src/core/Platform.sol";
import {RevenueRouter, IRevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";

contract RevenueRouterUpgrade438SonicTest is Test {
    uint public constant FORK_BLOCK = 61773869; // Feb-02-2026 01:37:35 PM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public multisig;

    IXStaking public xStaking;
    IXToken public xToken;
    IRevenueRouter public revenueRouter;

    address public constant USER1 = address(0x1001);
    address public constant USER2 = address(0x1002);
    address public constant USER3 = address(0x698eDaCD0cc284aB731e1c57662f3d3989E8adB7);

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(PLATFORM).multisig();

        xStaking = IXStaking(SonicConstantsLib.XSTBL_XSTAKING);
        xToken = IXToken(SonicConstantsLib.TOKEN_XSTBL);
        revenueRouter = IRevenueRouter(SonicConstantsLib.REVENUE_ROUTER);

        _upgradeAndSetup();
    }

    function testFullBuyBackRate() public {
        assertEq(revenueRouter.buyBackRate(), 100);
        uint balWas = IERC20(SonicConstantsLib.TOKEN_PT_AUSDC_14AUG2025).balanceOf(address(revenueRouter));
        vm.prank(multisig);
        revenueRouter.processAccumulatedAssets(40);
        assertLt(IERC20(SonicConstantsLib.TOKEN_PT_AUSDC_14AUG2025).balanceOf(address(revenueRouter)), balWas);

        skip(5 days);
        assertGt(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(address(revenueRouter)), 0);
        revenueRouter.updatePeriod();
        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(address(revenueRouter)), 0);
    }

    function testHalfBuyBackRate() public {
        // ------------------------------- mint xToken and deposit to staking before upgrade
        _mintAndDepositToStaking(USER1, 500_000e18);
        _mintAndDepositToStaking(USER2, 3_000e18);

        uint pendingRevenueWas = revenueRouter.pendingRevenue();

        vm.prank(multisig);
        xStaking.allowRewardToken(SonicConstantsLib.TOKEN_PT_AUSDC_14AUG2025, true);
        assertEq(xStaking.isTokenAllowed(SonicConstantsLib.TOKEN_PT_AUSDC_14AUG2025), true);
        assertEq(xStaking.isTokenAllowed(SonicConstantsLib.TOKEN_USDT), false);

        vm.prank(multisig);
        revenueRouter.setBuyBackRate(50);
        assertEq(revenueRouter.buyBackRate(), 50);

        assertEq(revenueRouter.pendingRevenueAssets().length, 0);

        //console.log(revenueRouter.pendingRevenue());

        vm.prank(multisig);
        revenueRouter.processAccumulatedAssets(40);

        assertEq(revenueRouter.pendingRevenueAssets()[0], SonicConstantsLib.TOKEN_PT_AUSDC_14AUG2025);
        assertEq(revenueRouter.pendingRevenueAsset(SonicConstantsLib.TOKEN_PT_AUSDC_14AUG2025), 1600000);
        assertGt(revenueRouter.pendingRevenue(), pendingRevenueWas);

        vm.prank(multisig);
        revenueRouter.processAccumulatedAssets(40);
        assertEq(revenueRouter.pendingRevenueAsset(SonicConstantsLib.TOKEN_PT_AUSDC_14AUG2025), 3200000);

        vm.startPrank(multisig);
        revenueRouter.processAccumulatedAssets(40);
        revenueRouter.processAccumulatedAssets(40);
        revenueRouter.processAccumulatedAssets(40);
        revenueRouter.processAccumulatedAssets(40);
        revenueRouter.processAccumulatedAssets(40);
        revenueRouter.processAccumulatedAssets(40);
        revenueRouter.processAccumulatedAssets(40);
        vm.stopPrank();

        assertEq(IERC20(SonicConstantsLib.TOKEN_PT_AUSDC_14AUG2025).balanceOf(address(xStaking)), 0);
        skip(7 days);
        revenueRouter.updatePeriod();
        skip(1 days);

        assertEq(revenueRouter.pendingRevenueAssets().length, 0);
        assertGt(IERC20(SonicConstantsLib.TOKEN_PT_AUSDC_14AUG2025).balanceOf(address(xStaking)), 0);

        uint earnedUser1 = xStaking.earnedToken(SonicConstantsLib.TOKEN_PT_AUSDC_14AUG2025, USER1);
        assertGt(earnedUser1, 0);
        vm.prank(USER1);
        xStaking.getRewardToken(SonicConstantsLib.TOKEN_PT_AUSDC_14AUG2025);
        assertEq(IERC20(SonicConstantsLib.TOKEN_PT_AUSDC_14AUG2025).balanceOf(USER1), earnedUser1);
    }

    function _mintAndDepositToStaking(address user, uint amount) internal {
        deal(SonicConstantsLib.TOKEN_STBL, user, amount);

        vm.prank(user);
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(xToken), amount);

        vm.prank(user);
        xToken.enter(amount);

        vm.prank(user);
        IERC20(address(xToken)).approve(address(xStaking), amount);

        vm.prank(user);
        xStaking.deposit(amount);
    }

    function _upgradeAndSetup() internal {
        _upgradePlatform();

        // do it on prod
        vm.startPrank(multisig);
        revenueRouter.setBuyBackRate(100);
        address[] memory assets = new address[](1);
        assets[0] = SonicConstantsLib.TOKEN_PT_AUSDC_14AUG2025;
        uint[] memory amounts = new uint[](1);
        amounts[0] = 1e6;
        revenueRouter.setMinSwapAmounts(assets, amounts);
        amounts[0] = 2e6;
        revenueRouter.setMaxSwapAmounts(assets, amounts);
        vm.stopPrank();
    }

    function _upgradePlatform() internal {
        rewind(1 days);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](2);
        address[] memory implementations = new address[](2);

        proxies[0] = SonicConstantsLib.XSTBL_XSTAKING;
        proxies[1] = SonicConstantsLib.REVENUE_ROUTER;
        //proxies[2] = SonicConstantsLib.REVENUE_ROUTER;

        implementations[0] = address(new XStaking());
        implementations[1] = address(new RevenueRouter());
        //implementations[2] = address(new RevenueRouter());

        vm.startPrank(platform.multisig());
        platform.announcePlatformUpgrade("2026.02.0-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }
}
