// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockSetup} from "../base/MockSetup.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {XToken} from "../../src/tokenomics/XToken.sol";
import {RevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";
import {FeeTreasury} from "../../src/tokenomics/FeeTreasury.sol";
import {IXToken} from "../../src/interfaces/IXToken.sol";
import {IXStaking} from "../../src/interfaces/IXStaking.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IRevenueRouter} from "../../src/interfaces/IRevenueRouter.sol";
import {IDAO} from "../../src/interfaces/IDAO.sol";
import {DAO} from "../../src/tokenomics/DAO.sol";

contract XStakingTest is Test, MockSetup {
    using SafeERC20 for IERC20;

    address public mainToken;
    IXToken public xToken;
    IXStaking public xStaking;
    IRevenueRouter public revenueRouter;

    function setUp() public {
        mainToken = address(tokenA);
        Proxy xStakingProxy = new Proxy();
        xStakingProxy.initProxy(address(new XStaking()));
        Proxy xTokenProxy = new Proxy();
        xTokenProxy.initProxy(address(new XToken()));
        Proxy revenueRouterProxy = new Proxy();
        revenueRouterProxy.initProxy(address(new RevenueRouter()));
        Proxy feeTreasuryProxy = new Proxy();
        feeTreasuryProxy.initProxy(address(new FeeTreasury()));
        FeeTreasury(address(feeTreasuryProxy)).initialize(address(platform), platform.multisig());
        XStaking(address(xStakingProxy)).initialize(address(platform), address(xTokenProxy));
        XToken(address(xTokenProxy))
            .initialize(
                address(platform), mainToken, address(xStakingProxy), address(revenueRouterProxy), "xStability", "xSTBL"
            );
        RevenueRouter(address(revenueRouterProxy))
            .initialize(address(platform), address(xTokenProxy), address(feeTreasuryProxy));
        xToken = IXToken(address(xTokenProxy));
        xStaking = IXStaking(address(xStakingProxy));
        revenueRouter = IRevenueRouter(address(revenueRouterProxy));
    }

    function test_staking() public {
        assertEq(xStaking.xToken(), address(xToken));
        assertEq(xStaking.lastTimeRewardApplicable(), 0);
        assertEq(xStaking.totalSupply(), 0);
        assertEq(xStaking.periodFinish(), 0);
        assertEq(xStaking.lastUpdateTime(), 0);
        assertEq(xStaking.rewardPerTokenStored(), 0);
        assertEq(xStaking.rewardPerToken(), 0);
        assertEq(xStaking.rewardRate(), 0);
        assertEq(xStaking.storedRewardsPerUser(address(1)), 0);
        assertEq(xStaking.userRewardPerTokenStored(address(1)), 0);

        // mint xToken
        tokenA.mint(100e18);
        IERC20(mainToken).approve(address(xToken), 100e18);
        xToken.enter(100e18);

        // deposit to staking
        IERC20(address(xToken)).approve(address(xStaking), 100e18);
        xStaking.deposit(10e18);
        assertEq(xStaking.balanceOf(address(this)), 10e18);

        // make rewards from exit penalties
        xToken.exit(20e18);
        assertEq(xToken.pendingRebase(), 10e18);

        // rebase
        vm.warp(block.timestamp + 7 days);
        revenueRouter.updatePeriod();
        assertEq(xToken.pendingRebase(), 0);
        assertGt(xToken.lastDistributedPeriod(), 0);
        vm.warp(block.timestamp + 1 days);

        // claim rewards
        uint balanceWas = IERC20(address(xToken)).balanceOf(address(this));
        assertGt(xStaking.earned(address(this)), 0);
        xStaking.getReward();
        uint balanceChange = IERC20(address(xToken)).balanceOf(address(this)) - balanceWas;
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

    function testSyncStabilityDAOBalances() public {
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
        vm.expectRevert(XStaking.DaoNotInitialized.selector);
        xStaking.syncDAOBalances(users);

        // ------------------------------- Mint xToken and deposit to staking
        for (uint i; i < users.length; ++i) {
            tokenA.mint(amounts[i]);
            IERC20(address(tokenA)).safeTransfer(users[i], amounts[i]);

            vm.prank(users[i]);
            IERC20(mainToken).approve(address(xToken), amounts[i]);

            vm.prank(users[i]);
            xToken.enter(amounts[i]);

            vm.prank(users[i]);
            IERC20(address(xToken)).approve(address(xStaking), amounts[i]);

            vm.prank(users[i]);
            xStaking.deposit(amounts[i]);
        }

        // ------------------------------- Set up Stability DAO token
        IDAO dao = _createDAOInstance();
        vm.prank(platform.multisig());
        platform.setupStabilityDAO(address(dao));

        vm.prank(address(123));
        vm.expectRevert(IControllable.NotOperator.selector);
        xStaking.syncDAOBalances(users);

        assertEq(dao.balanceOf(users[0]), 0, "0: User0 has no dao tokens");
        assertEq(IERC20(address(xStaking)).balanceOf(users[0]), amounts[0], "0: User0 has xStaking");
        assertEq(dao.balanceOf(users[1]), 0, "0: User1 has no dao tokens");
        assertEq(IERC20(address(xStaking)).balanceOf(users[1]), amounts[1], "0: User1 has xStaking");
        assertEq(dao.balanceOf(users[2]), 0, "0: User2 has no dao tokens");
        assertEq(IERC20(address(xStaking)).balanceOf(users[2]), amounts[2], "0: User2 has xStaking");

        // ------------------------------- sync 1
        _updateMinimalPower(4000e18);

        vm.prank(platform.multisig());
        xStaking.syncDAOBalances(users);

        assertEq(dao.balanceOf(users[0]), 4_001e18, "1: User0");
        assertEq(dao.balanceOf(users[1]), 0, "1: User1");
        assertEq(dao.balanceOf(users[2]), 4_000e18, "1: User2");

        // ------------------------------- sync 2
        _updateMinimalPower(3000e18);

        assertEq(dao.balanceOf(users[0]), 4_001e18, "2: User0");
        assertEq(dao.balanceOf(users[1]), 0, "2: User1 (syncDAOBalances is not called)");
        assertEq(dao.balanceOf(users[2]), 4_000e18, "2: User2");

        {
            address operator = makeAddr("operator");

            vm.prank(platform.multisig());
            platform.addOperator(operator);

            vm.prank(operator);
            xStaking.syncDAOBalances(users);
        }

        assertEq(dao.balanceOf(users[0]), 4_001e18, "2.1: User0");
        assertEq(dao.balanceOf(users[1]), 3_999e18, "2.1: User1");
        assertEq(dao.balanceOf(users[2]), 4_000e18, "2.1: User2");

        // ------------------------------- sync 3
        _updateMinimalPower(4001e18);

        assertEq(dao.balanceOf(users[0]), 4_001e18, "3: User0");
        assertEq(dao.balanceOf(users[1]), 3_999e18, "3: User1 (syncDAOBalances is not called)");
        assertEq(dao.balanceOf(users[2]), 4_000e18, "3: User2 (syncDAOBalances is not called)");

        vm.prank(platform.multisig());
        xStaking.syncDAOBalances(users);

        assertEq(dao.balanceOf(users[0]), 4_001e18, "3.1: User0");
        assertEq(dao.balanceOf(users[1]), 0, "3.1: User1");
        assertEq(dao.balanceOf(users[2]), 0, "3.1: User2");
    }

    function testPowerDelegation() public {
        IDAO dao = _createDAOInstance();

        address[] memory users = new address[](3);
        users[0] = address(1);
        users[1] = address(2);
        users[2] = address(3);
        uint72[3] memory amounts = [100e18, 150e18, 300e18];

        // ------------------------------- mint xToken and deposit to staking
        for (uint i; i < users.length; ++i) {
            tokenA.mint(amounts[i]);
            IERC20(address(tokenA)).safeTransfer(users[i], amounts[i]);

            vm.prank(users[i]);
            IERC20(mainToken).approve(address(xToken), amounts[i]);

            vm.prank(users[i]);
            xToken.enter(amounts[i]);
        }

        // ------------------------------- Each user deposits half of their xToken to staking
        for (uint i; i < users.length; ++i) {
            vm.prank(users[i]);
            IERC20(address(xToken)).approve(address(xStaking), amounts[i]);

            vm.prank(users[i]);
            xStaking.deposit(amounts[i] / 2);

            assertEq(xStaking.balanceOf(users[i]), amounts[i] / 2, "initial balance");
            assertEq(dao.getVotes(users[i]), 0, "initial power is zero because dao is not initialized");
        }

        // ------------------------------- Initialize Stability DAO and sync users
        vm.prank(platform.multisig());
        platform.setupStabilityDAO(address(dao));

        vm.prank(platform.multisig());
        xStaking.syncDAOBalances(users);

        for (uint i; i < users.length; ++i) {
            assertEq(xStaking.balanceOf(users[i]), amounts[i] / 2, "initial balance");
            assertEq(dao.getVotes(users[i]), amounts[i] / 2, "initial power");
        }

        // ------------------------------- 1: 0 => 1
        vm.prank(users[0]);
        dao.setPowerDelegation(users[2]);

        vm.expectRevert(IDAO.AlreadyDelegated.selector);
        vm.prank(users[0]);
        dao.setPowerDelegation(users[2]);

        vm.prank(users[0]);
        dao.setPowerDelegation(users[0]);

        vm.prank(users[0]);
        dao.setPowerDelegation(users[1]);

        assertEq(dao.getVotes(users[0]), 0, "1: User 0 delegated his power to user 1");
        assertEq(
            dao.getVotes(users[1]), amounts[1] / 2 + amounts[0] / 2, "1: balance user 1 + delegated power of user 0"
        );
        assertEq(dao.getVotes(users[2]), amounts[2] / 2, "1: balance user 2");

        // ------------------------------- 2: 1 => 2
        vm.prank(users[1]);
        dao.setPowerDelegation(users[2]);

        assertEq(dao.getVotes(users[0]), 0, "2: User 0 delegated his power to user 1");
        assertEq(dao.getVotes(users[1]), amounts[0] / 2, "2: delegated power of user 0");
        assertEq(
            dao.getVotes(users[2]), amounts[2] / 2 + amounts[1] / 2, "2: balance user 2 + delegated power of user 1"
        );

        // ------------------------------- A: 2 => 1
        vm.prank(users[2]);
        dao.setPowerDelegation(users[1]);

        assertEq(dao.getVotes(users[0]), 0, "A: no power");
        assertEq(dao.getVotes(users[1]), amounts[0] / 2 + amounts[2] / 2, "A: delegated power of users 0 and 2");
        assertEq(dao.getVotes(users[2]), amounts[1] / 2, "A: delegated power of user 1");

        {
            (address delegatedTo, address[] memory delegatedFrom) = dao.delegates(users[1]);
            assertEq(delegatedTo, users[2], "A: user 1 has delegated his power to user 2");
            assertEq(delegatedFrom.length, 2, "A: single user (2) has delegated to user 0");
            assertEq(delegatedFrom[0], users[0], "A: user 0 has delegated to user 1");
            assertEq(delegatedFrom[1], users[2], "A: user 2 has delegated to user 1");
        }

        // ------------------------------- 3: 2 => 0
        vm.prank(users[2]);
        dao.setPowerDelegation(address(0));

        vm.prank(users[2]);
        dao.setPowerDelegation(users[0]);

        assertEq(dao.getVotes(users[0]), amounts[2] / 2, "3: delegated power of user 2");
        assertEq(dao.getVotes(users[1]), amounts[0] / 2, "3: delegated power of user 0");
        assertEq(dao.getVotes(users[2]), amounts[1] / 2, "3: delegated power of user 1");

        // ------------------------------- 4: Each user deposits second half of their xToken to staking
        for (uint i; i < users.length; ++i) {
            vm.prank(users[i]);
            xStaking.deposit(amounts[i] / 2);

            assertEq(xStaking.balanceOf(users[i]), amounts[i], "full balance");
        }

        assertEq(dao.getVotes(users[0]), amounts[2], "4: delegated power of user 2");
        assertEq(dao.getVotes(users[1]), amounts[0], "4: delegated power of user 0");
        assertEq(dao.getVotes(users[2]), amounts[1], "4: delegated power of user 1");

        // ------------------------------- 5: User 1 withdraws half of his stake
        vm.prank(users[1]);
        xStaking.withdraw(amounts[1] / 2);

        assertEq(dao.getVotes(users[0]), amounts[2], "5: delegated power of user 2");
        assertEq(dao.getVotes(users[1]), amounts[0], "5: delegated power of user 0");
        assertEq(dao.getVotes(users[2]), amounts[1] / 2, "5: delegated power of user 1");

        // ------------------------------- 6: User 1 removes delegation
        vm.prank(users[1]);
        dao.setPowerDelegation(users[1]);

        assertEq(dao.getVotes(users[0]), amounts[2], "6: delegated power of user 2");
        assertEq(dao.getVotes(users[1]), amounts[1] / 2 + amounts[0], "6: delegated power of user 0");
        assertEq(dao.getVotes(users[2]), 0, "6: all power was delegated to user 0");

        {
            (address delegatedTo, address[] memory delegatedFrom) = dao.delegates(users[0]);
            assertEq(delegatedTo, users[1], "6: user 0 has delegated his power to user 1");
            assertEq(delegatedFrom.length, 1, "6: single user (2) has delegated to user 0");
            assertEq(delegatedFrom[0], users[2], "6: user 2 has delegated to user 0");
        }

        {
            (address delegatedTo, address[] memory delegatedFrom) = dao.delegates(users[1]);
            assertEq(delegatedTo, address(0), "6: user 1 has not delegated power");
            assertEq(delegatedFrom.length, 1, "6: single user (0) has delegated to user 1");
            assertEq(delegatedFrom[0], users[0], "6: user 0 has delegated to user 1");
        }

        {
            (address delegatedTo, address[] memory delegatedFrom) = dao.delegates(users[2]);
            assertEq(delegatedTo, users[0], "6: user 2 has delegated his power to user 0");
            assertEq(delegatedFrom.length, 0, "6: no one has delegated to user 2");
        }

        // ------------------------------- 7: Users 0 and 2 remove delegations
        vm.prank(users[0]);
        dao.setPowerDelegation(users[0]); // remove using delegation to oneself

        vm.prank(users[2]);
        dao.setPowerDelegation(address(0)); // remove using zero address

        assertEq(dao.getVotes(users[0]), amounts[0], "7: user 0 has not delegated power");
        assertEq(dao.getVotes(users[1]), amounts[1] / 2, "7: user 1 has not delegated power");
        assertEq(dao.getVotes(users[2]), amounts[2], "7: user 2 has not delegated power");
    }

    //region --------------------------------- Utils
    function _createDAOInstance() internal returns (IDAO) {
        IDAO.DaoParams memory p = IDAO.DaoParams({
            minimalPower: 50e18,
            exitPenalty: 50_00,
            proposalThreshold: 10_000,
            quorum: 25_000,
            powerAllocationDelay: 86400
        });

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new DAO()));
        IDAO token = IDAO(address(proxy));
        token.initialize(address(platform), address(xToken), address(xStaking), p, "Stability DAO", "STBL_DAO");
        return token;
    }

    function _updateMinimalPower(uint minimalPower_) internal {
        IDAO daoToken = IDAO(platform.stabilityDAO());
        IDAO.DaoParams memory p = daoToken.config();
        p.minimalPower = minimalPower_;

        vm.prank(platform.multisig());
        daoToken.updateConfig(p);
    }
    //endregion --------------------------------- Utils
}
