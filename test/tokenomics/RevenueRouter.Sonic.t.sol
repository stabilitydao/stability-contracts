// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console, Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {XSTBL} from "../../src/tokenomics/XSTBL.sol";
import {RevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";
import {FeeTreasury} from "../../src/tokenomics/FeeTreasury.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IRevenueRouter} from "../../src/interfaces/IRevenueRouter.sol";
import {IXSTBL} from "../../src/interfaces/IXSTBL.sol";
import {IXStaking} from "../../src/interfaces/IXStaking.sol";

contract RevenueRouterTestSonic is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STBL = 0x78a76316F66224CBaCA6e70acB24D5ee5b2Bd2c7;
    address public multisig;
    IXSTBL public xStbl;
    IXStaking public xStaking;
    IRevenueRouter public revenueRouter;
    address public feeTreasury;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(15931000); // Mar-25-2025 07:11:27 PM +UTC
        multisig = IPlatform(PLATFORM).multisig();
    }

    function test_RevenueRouter_xStbl_feeTreasury() public {
        _deployWithXSTBLandFeeTreasury();

        deal(SonicConstantsLib.TOKEN_STBL, address(this), 1e10);
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(revenueRouter), 1e10);
        revenueRouter.processFeeAsset(SonicConstantsLib.TOKEN_STBL, 1e10);
        assertEq(revenueRouter.pendingRevenue(), 0);

        deal(SonicConstantsLib.TOKEN_STBL, address(this), 1e16);
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(revenueRouter), 1e16);
        revenueRouter.processFeeAsset(SonicConstantsLib.TOKEN_STBL, 1e16);
        assertEq(revenueRouter.pendingRevenue(), 5e15);

        deal(SonicConstantsLib.TOKEN_wETH, address(this), 1e16);
        IERC20(SonicConstantsLib.TOKEN_wETH).approve(address(revenueRouter), 1e16);
        revenueRouter.processFeeAsset(SonicConstantsLib.TOKEN_wETH, 1e16);
        uint pendingRevenue = revenueRouter.pendingRevenue();
        assertGt(pendingRevenue, 1e18);

        deal(SonicConstantsLib.TOKEN_STBL, address(this), 1e18);
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(xStbl), 1e18);
        xStbl.enter(1e18);
        IERC20(address(xStbl)).approve(address(xStaking), 1e18);
        xStaking.deposit(1e18);

        deal(SonicConstantsLib.TOKEN_STBL, address(1), 1e18);
        vm.startPrank(address(1));
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(xStbl), 1e18);
        xStbl.enter(1e18);
        xStbl.exit(1e18);
        vm.stopPrank();

        vm.expectRevert();
        revenueRouter.updatePeriod();

        vm.warp(block.timestamp + 7 days);
        revenueRouter.updatePeriod();
        assertEq(revenueRouter.activePeriod(), revenueRouter.getPeriod());

        vm.warp(block.timestamp + 31 minutes);
        uint assumedEarned = pendingRevenue + 5e17;
        assertLt(xStaking.earned(address(this)) - 1e6, assumedEarned);
        assertGt(xStaking.earned(address(this)) + 1e6, assumedEarned);

        deal(SonicConstantsLib.TOKEN_stkscUSD, address(this), 1e18);
        IERC20(SonicConstantsLib.TOKEN_stkscUSD).approve(address(revenueRouter), 1e18);
        revenueRouter.processFeeVault(SonicConstantsLib.TOKEN_stkscUSD, 1e18);
        assertEq(IERC20(SonicConstantsLib.TOKEN_stkscUSD).balanceOf(feeTreasury), 1e18);
    }

    function test_RevenueRouter_minimal() public {
        _deployMinimal();

        deal(SonicConstantsLib.TOKEN_STBL, address(this), 1e10);
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(revenueRouter), 1e10);
        revenueRouter.processFeeAsset(SonicConstantsLib.TOKEN_STBL, 1e10);
        assertEq(revenueRouter.pendingRevenue(), 0);

        deal(SonicConstantsLib.TOKEN_STBL, address(this), 1e16);
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(revenueRouter), 1e16);
        revenueRouter.processFeeAsset(SonicConstantsLib.TOKEN_STBL, 1e16);
        assertEq(revenueRouter.pendingRevenue(), 0);

        deal(SonicConstantsLib.TOKEN_wETH, address(this), 1e16);
        IERC20(SonicConstantsLib.TOKEN_wETH).approve(address(revenueRouter), 1e16);
        revenueRouter.processFeeAsset(SonicConstantsLib.TOKEN_wETH, 1e16);

        vm.expectRevert();
        revenueRouter.updatePeriod();

        vm.warp(block.timestamp + 7 days);
        revenueRouter.updatePeriod();
        assertEq(revenueRouter.activePeriod(), revenueRouter.getPeriod());

        deal(SonicConstantsLib.TOKEN_stkscUSD, address(this), 1e18);
        IERC20(SonicConstantsLib.TOKEN_stkscUSD).approve(address(revenueRouter), 1e18);
        revenueRouter.processFeeVault(SonicConstantsLib.TOKEN_stkscUSD, 1e18);
    }

    function _deployWithXSTBLandFeeTreasury() internal {
        Proxy xStakingProxy = new Proxy();
        xStakingProxy.initProxy(address(new XStaking()));
        Proxy xSTBLProxy = new Proxy();
        xSTBLProxy.initProxy(address(new XSTBL()));
        Proxy revenueRouterProxy = new Proxy();
        revenueRouterProxy.initProxy(address(new RevenueRouter()));
        Proxy feeTreasuryProxy = new Proxy();
        feeTreasuryProxy.initProxy(address(new FeeTreasury()));
        FeeTreasury(address(feeTreasuryProxy)).initialize(PLATFORM, IPlatform(PLATFORM).multisig());
        XStaking(address(xStakingProxy)).initialize(PLATFORM, address(xSTBLProxy));
        XSTBL(address(xSTBLProxy)).initialize(PLATFORM, STBL, address(xStakingProxy), address(revenueRouterProxy));
        RevenueRouter(address(revenueRouterProxy)).initialize(PLATFORM, address(xSTBLProxy), address(feeTreasuryProxy));
        xStbl = IXSTBL(address(xSTBLProxy));
        xStaking = IXStaking(address(xStakingProxy));
        revenueRouter = IRevenueRouter(address(revenueRouterProxy));
        feeTreasury = address(feeTreasuryProxy);
    }

    function _deployMinimal() internal {
        Proxy revenueRouterProxy = new Proxy();
        revenueRouterProxy.initProxy(address(new RevenueRouter()));
        Proxy feeTreasuryProxy = new Proxy();
        feeTreasuryProxy.initProxy(address(new FeeTreasury()));
        FeeTreasury(address(feeTreasuryProxy)).initialize(PLATFORM, IPlatform(PLATFORM).multisig());
        RevenueRouter(address(revenueRouterProxy)).initialize(PLATFORM, address(0), address(feeTreasuryProxy));
        revenueRouter = IRevenueRouter(address(revenueRouterProxy));
        feeTreasury = address(feeTreasuryProxy);
    }
}
