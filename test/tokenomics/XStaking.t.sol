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
import {IStabilityDAO} from "../../src/interfaces/IStabilityDAO.sol";
import {StabilityDAO} from "../../src/tokenomics/StabilityDAO.sol";
import {MockStabilityDAO} from "../../src/test/MockIStabilityDAO.sol";

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
        XSTBL(address(xSTBLProxy))
            .initialize(address(platform), stbl, address(xStakingProxy), address(revenueRouterProxy));
        RevenueRouter(address(revenueRouterProxy))
            .initialize(address(platform), address(xSTBLProxy), address(feeTreasuryProxy));
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
        vm.expectRevert(XStaking.StblDaoNotInitialized.selector);
        xStaking.syncStabilityDAOBalances(users);

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
        IStabilityDAO daoToken = _createStabilityDAOInstance();
        vm.prank(platform.multisig());
        platform.setupStabilityDAO(address(daoToken));

        vm.prank(address(123));
        vm.expectRevert(IControllable.NotMultisig.selector);
        xStaking.syncStabilityDAOBalances(users);

        _updateMinimalPower(4000e18);

        assertEq(daoToken.balanceOf(users[0]), 0, "0: User0 has no dao tokens");
        assertEq(IERC20(address(xStaking)).balanceOf(users[0]), amounts[0], "0: User0 has xStaking");
        assertEq(daoToken.balanceOf(users[1]), 0, "0: User1 has no dao tokens");
        assertEq(IERC20(address(xStaking)).balanceOf(users[1]), amounts[1], "0: User1 has xStaking");
        assertEq(daoToken.balanceOf(users[2]), 0, "0: User2 has no dao tokens");
        assertEq(IERC20(address(xStaking)).balanceOf(users[2]), amounts[2], "0: User2 has xStaking");

        // ------------------------------- sync 1
        vm.prank(platform.multisig());
        xStaking.syncStabilityDAOBalances(users);

        assertEq(daoToken.balanceOf(users[0]), 4_001e18, "1: User0");
        assertEq(daoToken.balanceOf(users[1]), 0, "1: User1");
        assertEq(daoToken.balanceOf(users[2]), 4_000e18, "1: User2");

        // ------------------------------- sync 2
        _updateMinimalPower(3000e18);

        assertEq(daoToken.balanceOf(users[0]), 4_001e18, "2: User0");
        assertEq(daoToken.balanceOf(users[1]), 0, "2: User1 (syncStabilityDAOBalances is not called)");
        assertEq(daoToken.balanceOf(users[2]), 4_000e18, "2: User2");

        vm.prank(platform.multisig());
        xStaking.syncStabilityDAOBalances(users);

        assertEq(daoToken.balanceOf(users[0]), 4_001e18, "2.1: User0");
        assertEq(daoToken.balanceOf(users[1]), 3_999e18, "2.1: User1");
        assertEq(daoToken.balanceOf(users[2]), 4_000e18, "2.1: User2");

        // ------------------------------- sync 3
        _updateMinimalPower(4001e18);

        assertEq(daoToken.balanceOf(users[0]), 4_001e18, "3: User0");
        assertEq(daoToken.balanceOf(users[1]), 3_999e18, "3: User1 (syncStabilityDAOBalances is not called)");
        assertEq(daoToken.balanceOf(users[2]), 4_000e18, "3: User2 (syncStabilityDAOBalances is not called)");

        vm.prank(platform.multisig());
        xStaking.syncStabilityDAOBalances(users);

        assertEq(daoToken.balanceOf(users[0]), 4_001e18, "3.1: User0");
        assertEq(daoToken.balanceOf(users[1]), 0, "3.1: User1");
        assertEq(daoToken.balanceOf(users[2]), 0, "3.1: User2");
    }

    //region --------------------------------- Utils
    function _createStabilityDAOInstance() internal returns (IStabilityDAO) {
        IStabilityDAO.DaoParams memory p = IStabilityDAO.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 50_00,
            proposalThreshold: 10_00,
            quorum: 25_00,
            powerAllocationDelay: 86400
        });

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new StabilityDAO()));
        IStabilityDAO token = IStabilityDAO(address(proxy));
        token.initialize(address(platform), address(xStbl), address(xStaking), p);
        return token;
    }

    function _updateMinimalPower(uint minimalPower_) internal {
        IStabilityDAO daoToken = IStabilityDAO(platform.stabilityDAO());
        IStabilityDAO.DaoParams memory p = daoToken.config();
        p.minimalPower = minimalPower_;

        vm.prank(platform.multisig());
        daoToken.updateConfig(p);
    }
    //endregion --------------------------------- Utils
}
