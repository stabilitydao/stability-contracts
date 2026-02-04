// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {IXToken} from "../../src/interfaces/IXToken.sol";
import {IXStaking} from "../../src/interfaces/IXStaking.sol";

contract XStakingUpgrade438SonicTest is Test {
    uint public constant FORK_BLOCK = 61200000; // Jan-26-2026 03:00:37 PM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public multisig;

    IXStaking public xStaking;
    IXToken public xToken;

    address public constant USER1 = address(0x1001);
    address public constant USER2 = address(0x1002);
    address public constant USER3 = address(0x1003);

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(PLATFORM).multisig();

        xStaking = IXStaking(SonicConstantsLib.XSTBL_XSTAKING);
        xToken = IXToken(SonicConstantsLib.TOKEN_XSTBL);

        deal(SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.REVENUE_ROUTER, 100e6);

        _upgradeAndSetup();
    }

    function testRewardTokens() public {
        // ------------------------------- mint xToken and deposit to staking before upgrade
        _mintAndDepositToStaking(USER1, 500000e18);
        _mintAndDepositToStaking(USER2, 3000e18);

        assertEq(xStaking.isTokenAllowed(SonicConstantsLib.TOKEN_USDC), true);
        assertEq(xStaking.isTokenAllowed(SonicConstantsLib.TOKEN_USDT), false);

        vm.startPrank(SonicConstantsLib.REVENUE_ROUTER);
        IERC20(SonicConstantsLib.TOKEN_USDC).approve(address(xStaking), type(uint).max);
        xStaking.notifyRewardAmountToken(SonicConstantsLib.TOKEN_USDC, 100e6);
        vm.stopPrank();

        uint user1Earned = xStaking.earnedToken(SonicConstantsLib.TOKEN_USDC, USER1);
        assertEq(user1Earned, 0);

        vm.warp(block.timestamp + 1 hours);
        user1Earned = xStaking.earnedToken(SonicConstantsLib.TOKEN_USDC, USER1);
        assertGt(user1Earned, 10e6);

        vm.prank(USER1);
        xStaking.getRewardToken(SonicConstantsLib.TOKEN_USDC);
        assertEq(IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(USER1), user1Earned);
    }

    function _mintAndDepositToStaking(address user, uint amount) internal {
        deal(SonicConstantsLib.TOKEN_STBL, user, amount);

        vm.prank(user);
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(xToken), amount);

        vm.prank(user);
        xToken.enter(amount);

        vm.prank(user);
        IERC20(address(xToken)).approve(address(xStaking), amount);

        vm.prank(user);
        xStaking.deposit(amount);
    }

    function _upgradeAndSetup() internal {
        _upgradePlatform();

        vm.prank(multisig);
        xStaking.allowRewardToken(SonicConstantsLib.TOKEN_USDC, true);
    }

    function _upgradePlatform() internal {
        rewind(1 days);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = SonicConstantsLib.XSTBL_XSTAKING;
        //proxies[1] = SonicConstantsLib.TOKEN_XSTBL;
        //proxies[2] = SonicConstantsLib.REVENUE_ROUTER;

        implementations[0] = address(new XStaking());
        //implementations[1] = address(new XToken());
        //implementations[2] = address(new RevenueRouter());

        vm.startPrank(platform.multisig());
        platform.announcePlatformUpgrade("2026.02.0-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }
}
