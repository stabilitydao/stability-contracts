// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {XStaking, IXStaking} from "../../src/tokenomics/XStaking.sol";
import {XToken} from "../../src/tokenomics/XToken.sol";
import {IXToken} from "../../src/interfaces/IXToken.sol";
import {Platform} from "../../src/core/Platform.sol";
import {RevenueRouter, IRevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";

contract RevenueRouterUpgrade438PlasmaTest is Test {
    uint public constant FORK_BLOCK = 13214844; // Feb-03-2026 07:23:20 PM +UTC
    address public constant PLATFORM = PlasmaConstantsLib.PLATFORM;
    address public multisig;

    IXStaking public xStaking;
    IXToken public xToken;
    IRevenueRouter public revenueRouter;
    IRecovery public recovery;

    address public constant USER1 = address(0x1001);
    address public constant USER2 = address(0x1002);
    address public constant USER3 = address(0x698eDaCD0cc284aB731e1c57662f3d3989E8adB7);

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("PLASMA_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(PLATFORM).multisig();

        xStaking = IXStaking(PlasmaConstantsLib.XSTBL_XSTAKING);
        xToken = IXToken(PlasmaConstantsLib.TOKEN_XSTBL);
        revenueRouter = IRevenueRouter(PlasmaConstantsLib.REVENUE_ROUTER);
        recovery = IRecovery(PlasmaConstantsLib.RECOVERY);

        _upgradeAndSetup();
    }

    function testZeroBuyBackRate() public {
        assertEq(revenueRouter.buyBackRate(), 0);

        _mintAndDepositToStaking(USER1, 50_000e18);

        vm.prank(multisig);
        revenueRouter.processAccumulatedAssets(40);

        skip(5 days);
        revenueRouter.updatePeriod();
        skip(1 hours);

        uint earnedUser1 = xStaking.earnedToken(PlasmaConstantsLib.TOKEN_WEETH, USER1);
        assertGt(earnedUser1, 0);
        vm.prank(USER1);
        xStaking.getRewardToken(PlasmaConstantsLib.TOKEN_WEETH);
        assertEq(IERC20(PlasmaConstantsLib.TOKEN_WEETH).balanceOf(USER1), earnedUser1);

    }

    function _mintAndDepositToStaking(address user, uint amount) internal {
        deal(PlasmaConstantsLib.TOKEN_STBL, user, amount);

        vm.prank(user);
        IERC20(PlasmaConstantsLib.TOKEN_STBL).approve(address(xToken), amount);

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
        xStaking.allowRewardToken(PlasmaConstantsLib.TOKEN_WEETH, true);

        address[] memory addresses_ = new address[](4);
        addresses_[0] = PlasmaConstantsLib.TOKEN_STBL;
        addresses_[1] = PlasmaConstantsLib.TOKEN_XSTBL;
        addresses_[2] = PlasmaConstantsLib.XSTBL_XSTAKING;
        addresses_[3] = address(0);
        revenueRouter.setAddresses(addresses_);

        recovery.changeWhitelist(address(revenueRouter), true);

        vm.stopPrank();
    }

    function _upgradePlatform() internal {
        rewind(1 days);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](2);
        address[] memory implementations = new address[](2);

        proxies[0] = PlasmaConstantsLib.XSTBL_XSTAKING;
        proxies[1] = PlasmaConstantsLib.REVENUE_ROUTER;
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
