// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
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
import {Platform} from "../../src/core/Platform.sol";

contract RevenueRouterTestSonic is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public constant STBL = SonicConstantsLib.TOKEN_STBL;
    address public multisig;
    IXSTBL public xStbl;
    IXStaking public xStaking;
    IRevenueRouter public revenueRouter;
    address public feeTreasury;

    uint private constant FORK_BLOCK = 15931000; // Mar-25-2025 07:11:27 PM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        multisig = IPlatform(PLATFORM).multisig();
        _upgradePlatform();
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
        assertEq(revenueRouter.pendingRevenue(), 0);

        deal(SonicConstantsLib.TOKEN_WETH, address(this), 1e16);
        IERC20(SonicConstantsLib.TOKEN_WETH).approve(address(revenueRouter), 1e16);
        revenueRouter.processFeeAsset(SonicConstantsLib.TOKEN_WETH, 1e16);
        //uint pendingRevenue = revenueRouter.pendingRevenue();
        //assertGt(pendingRevenue, 1e18);

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

        /*vm.warp(block.timestamp + 31 minutes);
        uint assumedEarned = pendingRevenue + 5e17;
        assertLt(xStaking.earned(address(this)) - 1e6, assumedEarned);
        assertGt(xStaking.earned(address(this)) + 1e6, assumedEarned);*/

        /*deal(SonicConstantsLib.VAULT_C_USDC_SCUSD_ISF_SCUSD, address(this), 1e18);
        IERC20(SonicConstantsLib.VAULT_C_USDC_SCUSD_ISF_SCUSD).approve(address(revenueRouter), 1e18);
        revenueRouter.processFeeVault(SonicConstantsLib.VAULT_C_USDC_SCUSD_ISF_SCUSD, 1e18);
        assertEq(IERC20(SonicConstantsLib.VAULT_C_USDC_SCUSD_ISF_SCUSD).balanceOf(feeTreasury), 1e18);*/
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

        deal(SonicConstantsLib.TOKEN_WETH, address(this), 1e16);
        IERC20(SonicConstantsLib.TOKEN_WETH).approve(address(revenueRouter), 1e16);
        revenueRouter.processFeeAsset(SonicConstantsLib.TOKEN_WETH, 1e16);

        vm.expectRevert();
        revenueRouter.updatePeriod();

        vm.warp(block.timestamp + 7 days);
        revenueRouter.updatePeriod();
        assertEq(revenueRouter.activePeriod(), revenueRouter.getPeriod());

        /*deal(SonicConstantsLib.VAULT_C_USDC_SCUSD_ISF_SCUSD, address(this), 1e18);
        IERC20(SonicConstantsLib.VAULT_C_USDC_SCUSD_ISF_SCUSD).approve(address(revenueRouter), 1e18);
        revenueRouter.processFeeVault(SonicConstantsLib.VAULT_C_USDC_SCUSD_ISF_SCUSD, 1e18);*/
    }

    function testAddresses() public {
        _deployWithXSTBLandFeeTreasury();

        address[] memory addresses = revenueRouter.addresses();
        assertEq(addresses[0], address(STBL));
        assertEq(addresses[1], address(xStbl));
        assertEq(addresses[2], address(xStaking));
        assertEq(addresses[3], address(feeTreasury));
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

    function _upgradePlatform() internal {
        rewind(1 days);

        IPlatform platform = IPlatform(SonicConstantsLib.PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = SonicConstantsLib.PLATFORM;

        implementations[0] = address(new Platform());

        vm.startPrank(platform.multisig());
        platform.announcePlatformUpgrade("2025.08.21-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }
}
