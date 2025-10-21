// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";
import {IXSTBL} from "../../src/interfaces/IXSTBL.sol";
import {IStabilityDAO} from "../../src/interfaces/IStabilityDAO.sol";
import {XSTBL} from "../../src/tokenomics/XSTBL.sol";
import {Platform} from "../../src/core/Platform.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {StabilityDAO} from "../../src/tokenomics/StabilityDAO.sol";

contract XstblUpgrade406SonicTest is Test {
    uint public constant FORK_BLOCK = 50689527; // Oct-15-2025 05:17:06 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IRevenueRouter internal revenueRouter;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        revenueRouter = IRevenueRouter(IPlatform(PLATFORM).revenueRouter());
    }

    function testUpgradeXSTBLVesting() public {
        IXSTBL xstbl = IXSTBL(SonicConstantsLib.TOKEN_XSTBL);

        _upgradePlatform();
        IStabilityDAO daoToken = _setupStblDao();

        uint baseAmount = 100e18;

        // -------------- get STBL on balance
        deal(SonicConstantsLib.TOKEN_STBL, address(this), baseAmount);

        // -------------- enter to xSTBL
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(xstbl), type(uint).max);
        xstbl.enter(baseAmount);
        uint xstblBalance = IERC20(address(xstbl)).balanceOf(address(this));
        assertEq(xstblBalance, baseAmount, "xstbl balance after enter");

        // -------------- create vest
        xstbl.createVest(baseAmount);
        assertEq(xstbl.usersTotalVests(address(this)), 1, "now user has a vest");

        // -------------- wait min period (14 days) to be able to exit vest w/o cancellation
        skip(14 days);

        // -------------- try to exit vest with penalty 50% and check results
        (uint exitedAmount50, uint pendingRebaseDelta50) = _tryToExitVest(xstbl, address(this), 0);

        // -------------- change penalty to 80%
        {
            IStabilityDAO.DaoParams memory p = daoToken.config();
            p.exitPenalty = 80_00;

            vm.prank(SonicConstantsLib.MULTISIG);
            daoToken.updateConfig(p);
        }

        // -------------- try to exit vest with penalty 80% and check results
        (uint exitedAmount20, uint pendingRebaseDelta80) = _tryToExitVest(xstbl, address(this), 0);

        // -------------- check results (14 days of 180 were passed)
        assertEq(exitedAmount50, baseAmount * (100 - 50) / 100 + baseAmount * 50 / 100 * 14 / 180, "exitedAmount50");
        assertEq(exitedAmount50 + pendingRebaseDelta50, baseAmount, "50: total 100%");

        assertEq(exitedAmount20, baseAmount * (100 - 80) / 100 + baseAmount * 80 / 100 * 14 / 180, "exitedAmount80");
        assertEq(exitedAmount20 + pendingRebaseDelta80, baseAmount, "80: total 100%");
    }

    function testUpgradeXSTBLExit() public {
        IXSTBL xstbl = IXSTBL(SonicConstantsLib.TOKEN_XSTBL);
        _upgradePlatform();
        IStabilityDAO daoToken = _setupStblDao();

        uint baseAmount = 100e18;
        // -------------- get STBL on balance
        deal(SonicConstantsLib.TOKEN_STBL, address(this), baseAmount);

        // -------------- enter to xSTBL
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(xstbl), type(uint).max);
        xstbl.enter(baseAmount);
        uint xstblBalance = IERC20(address(xstbl)).balanceOf(address(this));
        assertEq(xstblBalance, baseAmount, "xstbl balance after enter");

        // -------------- try to exit vest with penalty 50% and check results
        (uint exitedAmount50, uint pendingRebaseDelta50) = _tryToExit(xstbl, address(this), baseAmount);

        // -------------- change penalty to 80%
        {
            IStabilityDAO.DaoParams memory p = daoToken.config();
            p.exitPenalty = 80_00;

            vm.prank(SonicConstantsLib.MULTISIG);
            daoToken.updateConfig(p);
        }

        // -------------- try to exit vest with penalty 80% and check results
        (uint exitedAmount20, uint pendingRebaseDelta80) = _tryToExit(xstbl, address(this), baseAmount);

        // -------------- check results (14 days of 180 were passed)
        assertEq(exitedAmount50, baseAmount * 50 / 100, "exitedAmount 50%");
        assertEq(pendingRebaseDelta50, baseAmount * 50 / 100, "penalty 50%");

        assertEq(exitedAmount20, baseAmount * (100 - 80) / 100, "exitedAmount 20%");
        assertEq(pendingRebaseDelta80, baseAmount * 80 / 100, "penalty 80%");

        assertEq(exitedAmount50 + pendingRebaseDelta50, baseAmount, "total 100%");
        assertEq(exitedAmount20 + pendingRebaseDelta80, baseAmount, "total 100%");
    }

    function testUpgradeXSTBLExitNoStabilityDao() public {
        IXSTBL xstbl = IXSTBL(SonicConstantsLib.TOKEN_XSTBL);
        _upgradePlatform();

        // Stability DAO is not initialized

        uint baseAmount = 100e18;
        // -------------- get STBL on balance
        deal(SonicConstantsLib.TOKEN_STBL, address(this), baseAmount);

        // -------------- enter to xSTBL
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(xstbl), type(uint).max);
        xstbl.enter(baseAmount);
        uint xstblBalance = IERC20(address(xstbl)).balanceOf(address(this));
        assertEq(xstblBalance, baseAmount, "xstbl balance after enter");

        // -------------- try to exit vest with penalty 50% and check results
        (uint exitedAmount50, uint pendingRebaseDelta50) = _tryToExit(xstbl, address(this), baseAmount);

        // -------------- check results (14 days of 180 were passed)
        assertEq(exitedAmount50, baseAmount * 50 / 100, "exitedAmount 50%");
        assertEq(pendingRebaseDelta50, baseAmount * 50 / 100, "penalty 50%");
        assertEq(exitedAmount50 + pendingRebaseDelta50, baseAmount, "total 100%");
    }

    //region -------------------------------- Internal logic
    function _tryToExitVest(
        IXSTBL xstbl,
        address user,
        uint vestId
    ) internal returns (uint exitedAmount, uint pendingRebaseDelta) {
        uint snapshot = vm.snapshotState();

        uint pendingRebaseBefore = IXSTBL(SonicConstantsLib.TOKEN_XSTBL).pendingRebase();
        uint balanceBefore = IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(user);
        xstbl.exitVest(vestId);
        uint balanceAfter = IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(user);
        uint pendingRebaseAfter = IXSTBL(SonicConstantsLib.TOKEN_XSTBL).pendingRebase();

        exitedAmount = balanceAfter - balanceBefore;
        pendingRebaseDelta = pendingRebaseAfter - pendingRebaseBefore;

        vm.revertToState(snapshot);
    }

    function _tryToExit(
        IXSTBL xstbl,
        address user,
        uint amount
    ) internal returns (uint exitedAmount, uint pendingRebaseDelta) {
        uint snapshot = vm.snapshotState();

        uint pendingRebaseBefore = IXSTBL(SonicConstantsLib.TOKEN_XSTBL).pendingRebase();
        uint balanceBefore = IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(user);
        xstbl.exit(amount);
        uint balanceAfter = IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(user);
        uint pendingRebaseAfter = IXSTBL(SonicConstantsLib.TOKEN_XSTBL).pendingRebase();

        exitedAmount = balanceAfter - balanceBefore;
        pendingRebaseDelta = pendingRebaseAfter - pendingRebaseBefore;

        vm.revertToState(snapshot);
    }

    //endregion -------------------------------- Internal logic

    //region -------------------------------- Helpers
    function _upgradePlatform() internal {
        rewind(1 days);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](2);
        address[] memory implementations = new address[](2);

        proxies[0] = SonicConstantsLib.TOKEN_XSTBL;
        proxies[1] = SonicConstantsLib.PLATFORM;

        implementations[0] = address(new XSTBL());
        implementations[1] = address(new Platform());

        vm.startPrank(SonicConstantsLib.MULTISIG);
        platform.cancelUpgrade();

        vm.startPrank(SonicConstantsLib.MULTISIG);
        platform.announcePlatformUpgrade("2025.10.02-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }

    function _setupStblDao() internal returns (IStabilityDAO) {
        IStabilityDAO dest = _createStabilityDAOInstance();

        vm.prank(SonicConstantsLib.MULTISIG);
        IPlatform(SonicConstantsLib.PLATFORM).setupStabilityDAO(address(dest));
        return dest;
    }

    function _createStabilityDAOInstance() internal returns (IStabilityDAO) {
        IStabilityDAO.DaoParams memory p = IStabilityDAO.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 0, // default 50%
            quorum: 15_00,
            proposalThreshold: 25_00,
            powerAllocationDelay: 86400
        });

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new StabilityDAO()));
        IStabilityDAO token = IStabilityDAO(address(proxy));
        token.initialize(SonicConstantsLib.PLATFORM, SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.XSTBL_XSTAKING, p);

        return token;
    }
    //endregion -------------------------------- Helpers
}
