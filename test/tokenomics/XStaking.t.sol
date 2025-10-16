// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
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
import {StabilityDaoToken} from "../../src/tokenomics/StabilityDaoToken.sol";
import {MockStabilityDaoToken} from "../../src/test/MockIStabilityDaoToken.sol";

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

    function testInitializeStabilityDaoToken() public {
        assertEq(xStaking.stabilityDaoToken(), address(0), "Not initialized");

        vm.prank(address(1));
        vm.expectRevert(IControllable.NotMultisig.selector);
        xStaking.initializeStabilityDaoToken(address(2));

        vm.prank(platform.multisig());
        xStaking.initializeStabilityDaoToken(address(2));
        assertEq(xStaking.stabilityDaoToken(), address(2), "Initialized");

        vm.prank(platform.multisig());
        vm.expectRevert(XStaking.AlreadyInitialized.selector);
        xStaking.initializeStabilityDaoToken(address(3));
    }

    function testPowerDelegation() public {
        address[3] memory users = [address(1), address(2), address(3)];
        uint72[3] memory amounts = [100e18, 150e18, 300e18];

        // ------------------------------- mint xSTBL and deposit to staking
        for (uint i; i < users.length; ++i) {
            tokenA.mint(amounts[i]);
            tokenA.transfer(users[i], amounts[i]);

            vm.prank(users[i]);
            IERC20(stbl).approve(address(xStbl), amounts[i]);

            vm.prank(users[i]);
            xStbl.enter(amounts[i]);
        }

        // ------------------------------- Each user deposits half of their xSTBL to staking
        for (uint i; i < users.length; ++i) {
            vm.prank(users[i]);
            IERC20(address(xStbl)).approve(address(xStaking), amounts[i]);

            vm.prank(users[i]);
            xStaking.deposit(amounts[i] / 2);

            assertEq(xStaking.balanceOf(users[i]), amounts[i] / 2);
            assertEq(xStaking.userPower(users[i]), amounts[i] / 2);
        }

        // ------------------------------- Initialize dao token
        vm.expectRevert(XStaking.StblDaoNotInitialized.selector);
        vm.prank(users[0]);
        xStaking.changePowerDelegation(users[1], true);

        vm.prank(platform.multisig());
        xStaking.initializeStabilityDaoToken(address(new MockStabilityDaoToken()));

        // ------------------------------- 1: 0 => 1
        vm.prank(users[0]);
        xStaking.changePowerDelegation(users[2], true);

        vm.expectRevert(XStaking.AlreadyDelegated.selector);
        vm.prank(users[0]);
        xStaking.changePowerDelegation(users[2], true);

        vm.prank(users[0]);
        xStaking.changePowerDelegation(users[2], false);

        vm.prank(users[0]);
        xStaking.changePowerDelegation(users[1], true);

        assertEq(xStaking.userPower(users[0]), 0, "1: User 0 has delegates his power to user 1");
        assertEq(xStaking.userPower(users[1]), amounts[1] / 2 + amounts[0] / 2, "1: balance user 1 + delegated power of user 0");
        assertEq(xStaking.userPower(users[2]), amounts[2] / 2, "1: balance user 2");

        // ------------------------------- 2: 1 => 2
        vm.prank(users[1]);
        xStaking.changePowerDelegation(users[2], true);

        assertEq(xStaking.userPower(users[0]), 0, "2: User 0 has delegates his power to user 1");
        assertEq(xStaking.userPower(users[1]), amounts[0] / 2, "2: delegated power of user 0");
        assertEq(xStaking.userPower(users[2]), amounts[2] / 2 + amounts[1] / 2, "2: balance user 2 + delegated power of user 1");

        // ------------------------------- 3: 2 => 0
        vm.prank(users[2]);
        xStaking.changePowerDelegation(users[0], true);

        assertEq(xStaking.userPower(users[0]), amounts[2] / 2, "3: delegated power of user 2");
        assertEq(xStaking.userPower(users[1]), amounts[0] / 2, "3: delegated power of user 0");
        assertEq(xStaking.userPower(users[2]), amounts[1] / 2, "3: delegated power of user 1");

        // ------------------------------- 4: Each user deposits second half of their xSTBL to staking
        for (uint i; i < users.length; ++i) {
            vm.prank(users[i]);
            xStaking.deposit(amounts[i] / 2);

            assertEq(xStaking.balanceOf(users[i]), amounts[i], "full balance");
        }

        assertEq(xStaking.userPower(users[0]), amounts[2], "4: delegated power of user 2");
        assertEq(xStaking.userPower(users[1]), amounts[0], "4: delegated power of user 0");
        assertEq(xStaking.userPower(users[2]), amounts[1], "4: delegated power of user 1");

        // ------------------------------- 5: User 1 withdraws half of his stake
        vm.prank(users[1]);
        xStaking.withdraw(amounts[1] / 2);

        assertEq(xStaking.userPower(users[0]), amounts[2], "5: delegated power of user 2");
        assertEq(xStaking.userPower(users[1]), amounts[0], "5: delegated power of user 0");
        assertEq(xStaking.userPower(users[2]), amounts[1] / 2, "5: delegated power of user 1");

        // ------------------------------- 6: User 1 removes delegation
        vm.prank(users[1]);
        xStaking.changePowerDelegation(address(0), false);

        assertEq(xStaking.userPower(users[0]), amounts[2], "6: delegated power of user 2");
        assertEq(xStaking.userPower(users[1]), amounts[1] / 2 + amounts[0], "6: delegated power of user 0");
        assertEq(xStaking.userPower(users[2]), 0, "6: all power was delegated to user 0");

        // ------------------------------- 7: Users 0 and 2 remove delegations
        vm.prank(users[0]);
        xStaking.changePowerDelegation(address(0), false);
        vm.prank(users[2]);
        xStaking.changePowerDelegation(address(0), false);

        assertEq(xStaking.userPower(users[0]), amounts[0], "7: user 0 has not delegated power");
        assertEq(xStaking.userPower(users[1]), amounts[1] / 2, "6: user 1 has not delegated power");
        assertEq(xStaking.userPower(users[2]), amounts[2], "6: user 2 has not delegated power");
    }
}
