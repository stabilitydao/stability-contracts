// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RevenueRouter, IRevenueRouter, IControllable} from "../../src/tokenomics/RevenueRouter.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IXSTBL} from "../../src/interfaces/IXSTBL.sol";
import {Platform} from "../../src/core/Platform.sol";
import {XSTBL} from "../../src/tokenomics/XSTBL.sol";

contract XstblUpgrade406SonicTest is Test {
    uint public constant FORK_BLOCK = 50689527; // Oct-15-2025 05:17:06 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IXSTBL internal xstbl;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        xstbl = IXSTBL(SonicConstantsLib.TOKEN_XSTBL);
    }

    function testUpgradeXSTBL() public {
        uint baseAmount = 100e18;
        // -------------- get STBL on balance
        deal(SonicConstantsLib.TOKEN_STBL, address(this), baseAmount);

        // -------------- enter to xSTBL
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(xstbl), type(uint).max);
        xstbl.enter(baseAmount);
        uint xstblBalance = IERC20(SonicConstantsLib.TOKEN_XSTBL).balanceOf(address(this));
        assertEq(xstblBalance, baseAmount, "xstbl balance after enter");

        // -------------- create vest
        xstbl.createVest(baseAmount);
        assertEq(xstbl.usersTotalVests(address(this)), 1, "now user has a vest");

        // -------------- wait min period (14 days) to be able to exit vest w/o cancellation
        skip(14 days);

        // -------------- try to exit vest with penalty 50% and check results
        uint exitedAmount50 = _tryToExitVest(address(this), 0);

        // -------------- upgrade platform, change penalty to 80%
        _upgradePlatform();

        vm.prank(SonicConstantsLib.MULTISIG);
        xstbl.setSlashingPenalty(20_00);

        // -------------- try to exit vest with penalty 80% and check results
        uint exitedAmount20 = _tryToExitVest(address(this), 0);

        // -------------- check results (14 days of 180 were passed)
        assertEq(exitedAmount50, baseAmount * (100 - 50) / 100 * 14 / 180 + baseAmount * 50 / 100, "exitedAmount50");
        assertEq(exitedAmount20, baseAmount * (100 - 20) / 100 * 14 / 180 + baseAmount * 20 / 100, "exitedAmount20");
    }

    function _tryToExitVest(address user, uint vestId) internal returns (uint exitedAmount) {
        uint snapshot = vm.snapshotState();

        uint balanceBefore = IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(user);
        xstbl.exitVest(vestId);
        uint balanceAfter = IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(user);
        exitedAmount = balanceAfter - balanceBefore;

        vm.revertToState(snapshot);
    }

    function _upgradePlatform() internal {
        rewind(1 days);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = SonicConstantsLib.TOKEN_XSTBL;
        implementations[0] = address(new XSTBL());

        vm.startPrank(SonicConstantsLib.MULTISIG);
        platform.cancelUpgrade();

        vm.startPrank(SonicConstantsLib.MULTISIG);
        platform.announcePlatformUpgrade("2025.10.02-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }
}
