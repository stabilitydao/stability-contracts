// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";
import {MockSetup} from "../base/MockSetup.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {XSTBL} from "../../src/tokenomics/XSTBL.sol";
import {RevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";
import {FeeTreasury} from "../../src/tokenomics/FeeTreasury.sol";
import {IXSTBL} from "../../src/interfaces/IXSTBL.sol";
import {IXStaking} from "../../src/interfaces/IXStaking.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IRevenueRouter} from "../../src/interfaces/IRevenueRouter.sol";

contract XStakingTest is Test, MockSetup {
    address public stbl;
    IXSTBL public xStbl;
    IXStaking public xStaking;
    IRevenueRouter public revenueRouter;

    function setUp() public {
        stbl = address(tokenA);
        Proxy xStakingProxy = new Proxy();
        xStakingProxy.initProxy(address(new XStaking()));
        Proxy xSTBLProxy = new Proxy();
        xSTBLProxy.initProxy(address(new XSTBL()));
        Proxy revenueRouterProxy = new Proxy();
        revenueRouterProxy.initProxy(address(new RevenueRouter()));
        Proxy feeTreasuryProxy = new Proxy();
        feeTreasuryProxy.initProxy(address(new FeeTreasury()));
        FeeTreasury(address(feeTreasuryProxy)).initialize(address(platform), platform.multisig());
        XStaking(address(xStakingProxy)).initialize(address(platform), address(xSTBLProxy));
        XSTBL(address(xSTBLProxy)).initialize(
            address(platform), stbl, address(xStakingProxy), address(revenueRouterProxy)
        );
        RevenueRouter(address(revenueRouterProxy)).initialize(
            address(platform), address(xSTBLProxy), address(feeTreasuryProxy)
        );
        xStbl = IXSTBL(address(xSTBLProxy));
        xStaking = IXStaking(address(xStakingProxy));
        revenueRouter = IRevenueRouter(address(revenueRouterProxy));
    }

    function test_staking() public {
        assertEq(xStaking.xSTBL(), address(xStbl));
        assertEq(xStaking.lastTimeRewardApplicable(), 0);
        assertEq(xStaking.totalSupply(), 0);
        assertEq(xStaking.periodFinish(), 0);
        assertEq(xStaking.lastUpdateTime(), 0);
        assertEq(xStaking.rewardPerTokenStored(), 0);
        assertEq(xStaking.rewardPerToken(), 0);
        assertEq(xStaking.rewardRate(), 0);
        assertEq(xStaking.storedRewardsPerUser(address(1)), 0);
        assertEq(xStaking.userRewardPerTokenStored(address(1)), 0);

        // mint xSTBL
        tokenA.mint(100e18);
        IERC20(stbl).approve(address(xStbl), 100e18);
        xStbl.enter(100e18);

        // deposit to staking
        IERC20(address(xStbl)).approve(address(xStaking), 100e18);
        xStaking.deposit(10e18);
        assertEq(xStaking.balanceOf(address(this)), 10e18);

        // make rewards from exit penalties
        xStbl.exit(20e18);
        assertEq(xStbl.pendingRebase(), 10e18);

        // rebase
        vm.warp(block.timestamp + 7 days);
        revenueRouter.updatePeriod();
        assertEq(xStbl.pendingRebase(), 0);
        assertGt(xStbl.lastDistributedPeriod(), 0);
        vm.warp(block.timestamp + 1 days);

        // claim rewards
        uint balanceWas = IERC20(address(xStbl)).balanceOf(address(this));
        assertGt(xStaking.earned(address(this)), 0);
        xStaking.getReward();
        uint balanceChange = IERC20(address(xStbl)).balanceOf(address(this)) - balanceWas;
        assertGt(balanceChange, 0);

        xStaking.withdraw(1e18);
        xStaking.withdrawAll();
        xStaking.depositAll();

        vm.prank(address(1));
        vm.expectRevert();
        xStaking.setNewDuration(1 hours);
        xStaking.setNewDuration(1 hours);
        assertEq(xStaking.duration(), 1 hours);

        vm.expectRevert();
        xStaking.deposit(0);

        vm.expectRevert();
        xStaking.withdraw(0);

        vm.expectRevert();
        xStaking.notifyRewardAmount(0);
    }
}
