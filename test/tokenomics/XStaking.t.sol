// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

//import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
import {IStabilityDaoToken} from "../../src/interfaces/IStabilityDaoToken.sol";
import {StabilityDaoToken} from "../../src/tokenomics/StabilityDaoToken.sol";
import {MockStabilityDaoToken} from "../../src/test/MockIStabilityDaoToken.sol";

contract XStakingTest is Test, MockSetup {
    using SafeERC20 for IERC20;

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
            IERC20(address(tokenA)).safeTransfer(users[i], amounts[i]);

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
        xStaking.changePowerDelegation(users[1]);

        vm.prank(platform.multisig());
        xStaking.initializeStabilityDaoToken(address(new MockStabilityDaoToken()));

        // ------------------------------- 1: 0 => 1
        vm.prank(users[0]);
        xStaking.changePowerDelegation(users[2]);

        vm.expectRevert(XStaking.AlreadyDelegated.selector);
        vm.prank(users[0]);
        xStaking.changePowerDelegation(users[2]);

        vm.prank(users[0]);
        xStaking.changePowerDelegation(users[0]);

        vm.prank(users[0]);
        xStaking.changePowerDelegation(users[1]);

        assertEq(xStaking.userPower(users[0]), 0, "1: User 0 has delegates his power to user 1");
        assertEq(
            xStaking.userPower(users[1]),
            amounts[1] / 2 + amounts[0] / 2,
            "1: balance user 1 + delegated power of user 0"
        );
        assertEq(xStaking.userPower(users[2]), amounts[2] / 2, "1: balance user 2");

        // ------------------------------- 2: 1 => 2
        vm.prank(users[1]);
        xStaking.changePowerDelegation(users[2]);

        assertEq(xStaking.userPower(users[0]), 0, "2: User 0 has delegates his power to user 1");
        assertEq(xStaking.userPower(users[1]), amounts[0] / 2, "2: delegated power of user 0");
        assertEq(
            xStaking.userPower(users[2]),
            amounts[2] / 2 + amounts[1] / 2,
            "2: balance user 2 + delegated power of user 1"
        );

        // ------------------------------- 3: 2 => 0
        vm.prank(users[2]);
        xStaking.changePowerDelegation(users[0]);

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
        xStaking.changePowerDelegation(users[1]);

        assertEq(xStaking.userPower(users[0]), amounts[2], "6: delegated power of user 2");
        assertEq(xStaking.userPower(users[1]), amounts[1] / 2 + amounts[0], "6: delegated power of user 0");
        assertEq(xStaking.userPower(users[2]), 0, "6: all power was delegated to user 0");

        {
            (address delegatedTo, address[] memory delegatedFrom) = xStaking.delegates(users[0]);
            assertEq(delegatedTo, users[1], "6: user 0 has delegated his power to user 1");
            assertEq(delegatedFrom.length, 1, "6: single user (2) has delegated to user 0");
            assertEq(delegatedFrom[0], users[2], "6: user 2 has delegated to user 0");
        }

        {
            (address delegatedTo, address[] memory delegatedFrom) = xStaking.delegates(users[1]);
            assertEq(delegatedTo, address(0), "6: user 1 has not delegated power");
            assertEq(delegatedFrom.length, 1, "6: single user (0) has delegated to user 1");
            assertEq(delegatedFrom[0], users[0], "6: user 0 has delegated to user 1");
        }

        {
            (address delegatedTo, address[] memory delegatedFrom) = xStaking.delegates(users[2]);
            assertEq(delegatedTo, users[0], "6: user 2 has delegated his power to user 0");
            assertEq(delegatedFrom.length, 0, "6: no one has delegated to user 2");
        }

        // ------------------------------- 7: Users 0 and 2 remove delegations
        vm.prank(users[0]);
        xStaking.changePowerDelegation(users[0]);
        vm.prank(users[2]);
        xStaking.changePowerDelegation(users[2]);

        assertEq(xStaking.userPower(users[0]), amounts[0], "7: user 0 has not delegated power");
        assertEq(xStaking.userPower(users[1]), amounts[1] / 2, "7: user 1 has not delegated power");
        assertEq(xStaking.userPower(users[2]), amounts[2], "7: user 2 has not delegated power");
    }

    function testSyncStabilityDaoTokenBalances() public {
        address[] memory users = new address[](3);
        users[0] = address(1);
        users[1] = address(100);
        users[2] = address(200);

        uint[] memory amounts = new uint[](3);
        amounts[0] = 4_001e18;
        amounts[1] = 3_999e18;
        amounts[2] = 4_000e18;

        // ------------------------------- Bad paths
        vm.prank(platform.multisig());
        vm.expectRevert(XStaking.StblDaoNotInitialized.selector);
        xStaking.syncStabilityDaoTokenBalances(users);

        // ------------------------------- Mint xSTBL and deposit to staking
        for (uint i; i < users.length; ++i) {
            tokenA.mint(amounts[i]);
            IERC20(address(tokenA)).safeTransfer(users[i], amounts[i]);

            vm.prank(users[i]);
            IERC20(stbl).approve(address(xStbl), amounts[i]);

            vm.prank(users[i]);
            xStbl.enter(amounts[i]);

            vm.prank(users[i]);
            IERC20(address(xStbl)).approve(address(xStaking), amounts[i]);

            vm.prank(users[i]);
            xStaking.deposit(amounts[i]);
        }

        // ------------------------------- Set up dao token
        IStabilityDaoToken daoToken = _createStabilityDaoTokenInstance();
        vm.prank(platform.multisig());
        xStaking.initializeStabilityDaoToken(address(daoToken));

        vm.prank(address(123));
        vm.expectRevert(IControllable.NotMultisig.selector);
        xStaking.syncStabilityDaoTokenBalances(users);

        _updateConfig(4000e18);

        assertEq(daoToken.balanceOf(users[0]), 0, "0: User0 has no dao tokens");
        assertEq(IERC20(address(xStaking)).balanceOf(users[0]), amounts[0], "0: User0 has xStaking");
        assertEq(daoToken.balanceOf(users[1]), 0, "0: User1 has no dao tokens");
        assertEq(IERC20(address(xStaking)).balanceOf(users[1]), amounts[1], "0: User1 has xStaking");
        assertEq(daoToken.balanceOf(users[2]), 0, "0: User2 has no dao tokens");
        assertEq(IERC20(address(xStaking)).balanceOf(users[2]), amounts[2], "0: User2 has xStaking");

        // ------------------------------- sync 1
        vm.prank(platform.multisig());
        xStaking.syncStabilityDaoTokenBalances(users);

        assertEq(daoToken.balanceOf(users[0]), 4_001e18, "1: User0");
        assertEq(daoToken.balanceOf(users[1]), 0, "1: User1");
        assertEq(daoToken.balanceOf(users[2]), 4_000e18, "1: User2");

        // ------------------------------- sync 2
        _updateConfig(3000e18);

        assertEq(daoToken.balanceOf(users[0]), 4_001e18, "2: User0");
        assertEq(daoToken.balanceOf(users[1]), 0, "2: User1 (syncStabilityDaoTokenBalances is not called)");
        assertEq(daoToken.balanceOf(users[2]), 4_000e18, "2: User2");

        vm.prank(platform.multisig());
        xStaking.syncStabilityDaoTokenBalances(users);

        assertEq(daoToken.balanceOf(users[0]), 4_001e18, "2.1: User0");
        assertEq(daoToken.balanceOf(users[1]), 3_999e18, "2.1: User1");
        assertEq(daoToken.balanceOf(users[2]), 4_000e18, "2.1: User2");

        // ------------------------------- sync 3
        _updateConfig(4001e18);

        assertEq(daoToken.balanceOf(users[0]), 4_001e18, "3: User0");
        assertEq(daoToken.balanceOf(users[1]), 3_999e18, "3: User1 (syncStabilityDaoTokenBalances is not called)");
        assertEq(daoToken.balanceOf(users[2]), 4_000e18, "3: User2 (syncStabilityDaoTokenBalances is not called)");

        vm.prank(platform.multisig());
        xStaking.syncStabilityDaoTokenBalances(users);

        assertEq(daoToken.balanceOf(users[0]), 4_001e18, "3.1: User0");
        assertEq(daoToken.balanceOf(users[1]), 0, "3.1: User1");
        assertEq(daoToken.balanceOf(users[2]), 0, "3.1: User2");
    }

    //region --------------------------------- Utils
    function _createStabilityDaoTokenInstance() internal returns (IStabilityDaoToken) {
        IStabilityDaoToken.DaoParams memory p = IStabilityDaoToken.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 5_000,
            proposalThreshold: 100_000,
            powerAllocationDelay: 86400
        });

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new StabilityDaoToken()));
        IStabilityDaoToken token = IStabilityDaoToken(address(proxy));
        token.initialize(address(platform), address(xStbl), address(xStaking), p);
        return token;
    }

    function _updateConfig(uint minimalPower_) internal {
        IStabilityDaoToken daoToken = IStabilityDaoToken(xStaking.stabilityDaoToken());
        IStabilityDaoToken.DaoParams memory p = daoToken.config();
        p.minimalPower = minimalPower_;

        vm.prank(platform.multisig());
        daoToken.updateConfig(p);
    }
    //endregion --------------------------------- Utils
}
