// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IControllable} from "../../src/tokenomics/RevenueRouter.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {Factory} from "../../src/core/Factory.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {Platform} from "../../src/core/Platform.sol";
import {IStabilityDaoToken} from "../../src/interfaces/IStabilityDaoToken.sol";
import {StabilityDaoToken} from "../../src/tokenomics/StabilityDaoToken.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {XSTBL} from "../../src/tokenomics/XSTBL.sol";
import {IXSTBL} from "../../src/interfaces/IXSTBL.sol";
import {IXStaking} from "../../src/interfaces/IXStaking.sol";

contract XStakingUpgrade404SonicTest is Test {
    uint public constant FORK_BLOCK = 50941599; // Oct-17-2025 06:26:02 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public multisig;

    IXStaking public xStaking;
    IXSTBL public xStbl;

    address public constant USER1 = address(0x1001);
    address public constant USER2 = address(0x1002);
    address public constant USER3 = address(0x1003);

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(PLATFORM).multisig();

        xStaking = IXStaking(SonicConstantsLib.XSTBL_XSTAKING);
        xStbl = IXSTBL(SonicConstantsLib.TOKEN_XSTBL);
    }

    function testDepositWithdrawXStaking() public {
        // ------------------------------- mint xSTBL and deposit to staking before upgrade
        _mintAndDepositToStaking(USER1, 5000e18);
        _mintAndDepositToStaking(USER2, 3000e18);

        address[] memory users = new address[](3);
        users[0] = USER1;
        users[1] = USER2;
        users[2] = USER3;

        // ------------------------------- Upgrade and sync
        IStabilityDaoToken daoToken = _upgradeAndSetup();

        vm.prank(multisig);
        xStaking.syncStabilityDaoTokenBalances(users);

        assertEq(xStaking.userPower(USER1), 5000e18, "1: user 1 power");
        assertEq(xStaking.userPower(USER2), 3000e18, "1: user 2 power");
        assertEq(xStaking.userPower(USER3), 0, "1: user 3 power");

        assertEq(daoToken.balanceOf(USER1), 5000e18, "1: user 1 dao balance");
        assertEq(daoToken.balanceOf(USER2), 0, "1: user 2 dao balance");
        assertEq(daoToken.balanceOf(USER3), 0, "1: user 3 dao balance");

        // ------------------------------- Deposit and withdraw 2
        _mintAndDepositToStaking(USER2, 1000e18);
        _mintAndDepositToStaking(USER3, 4000e18);

        vm.prank(USER1);
        xStaking.withdraw(1000e18);

        assertEq(xStaking.userPower(USER1), 4000e18, "2: user 1 power");
        assertEq(xStaking.userPower(USER2), 4000e18, "2: user 2 power");
        assertEq(xStaking.userPower(USER3), 4000e18, "2: user 3 power");

        assertEq(daoToken.balanceOf(USER1), 4000e18, "2: user 1 dao balance");
        assertEq(daoToken.balanceOf(USER2), 4000e18, "2: user 2 dao balance");
        assertEq(daoToken.balanceOf(USER3), 4000e18, "2: user 3 dao balance");

        // ------------------------------- Deposit and withdraw 3
        _mintAndDepositToStaking(USER2, 1000e18);
        _mintAndDepositToStaking(USER3, 1000e18);

        vm.prank(USER1);
        xStaking.withdraw(1000e18);

        assertEq(xStaking.userPower(USER1), 3000e18, "3: user 1 power");
        assertEq(xStaking.userPower(USER2), 5000e18, "3: user 2 power");
        assertEq(xStaking.userPower(USER3), 5000e18, "3: user 3 power");

        assertEq(daoToken.balanceOf(USER1), 0, "3: user 1 dao balance");
        assertEq(daoToken.balanceOf(USER2), 5000e18, "3: user 2 dao balance");
        assertEq(daoToken.balanceOf(USER3), 5000e18, "3: user 3 dao balance");

        // ------------------------------- Deposit and withdraw 4
        _mintAndDepositToStaking(USER1, 5000e18);

        vm.prank(USER2);
        xStaking.withdraw(5000e18);

        vm.prank(USER3);
        xStaking.withdraw(1500e18);

        assertEq(xStaking.userPower(USER1), 8000e18, "4: user 1 power");
        assertEq(xStaking.userPower(USER2), 0, "4: user 2 power");
        assertEq(xStaking.userPower(USER3), 3500e18, "4: user 3 power");

        assertEq(daoToken.balanceOf(USER1), 8000e18, "4: user 1 dao balance");
        assertEq(daoToken.balanceOf(USER2), 0, "4: user 2 dao balance");
        assertEq(daoToken.balanceOf(USER3), 0, "4: user 3 dao balance");
    }

    function testDelegation() public {
        // ------------------------------- mint xSTBL and deposit to staking before upgrade
        address[] memory users = new address[](3);
        users[0] = USER1;
        users[1] = USER2;
        users[2] = USER3;

        uint power1 = 1001e18;
        uint power2 = 2002e18;
        uint power3 = 3003e18;

        // ------------------------------- Upgrade and sync
        IStabilityDaoToken daoToken = _upgradeAndSetup();

        vm.prank(multisig);
        xStaking.syncStabilityDaoTokenBalances(users);

        // ------------------------------- Deposit 1
        _mintAndDepositToStaking(USER1, power1);
        _mintAndDepositToStaking(USER2, power2);
        _mintAndDepositToStaking(USER3, power3);

        assertEq(xStaking.userPower(USER1), power1, "1: user 1 power");
        assertEq(xStaking.userPower(USER2), power2, "1: user 2 power");
        assertEq(xStaking.userPower(USER3), power3, "1: user 3 power");

        assertEq(daoToken.balanceOf(USER1), 0, "1: user 1 dao balance");
        assertEq(daoToken.balanceOf(USER2), 0, "1: user 2 dao balance");
        assertEq(daoToken.balanceOf(USER3), 0, "1: user 3 dao balance");

        // ------------------------------- Users 1 and 3 delegate to user 2
        vm.prank(USER1);
        xStaking.changePowerDelegation(USER2);

        vm.prank(USER3);
        xStaking.changePowerDelegation(USER2);

        assertEq(xStaking.userPower(USER1), 0, "2: user 1 power");
        assertEq(xStaking.userPower(USER2), power2 + power1 + power3, "2: user 2 power");
        assertEq(xStaking.userPower(USER3), 0, "2: user 3 power");

        assertEq(daoToken.balanceOf(USER1), 0, "2: user 1 dao balance");
        assertEq(daoToken.balanceOf(USER2), power2 + power1 + power3, "2: user 2 dao balance");
        assertEq(daoToken.balanceOf(USER3), 0, "2: user 3 dao balance");

        // ------------------------------- Clear delegation
        vm.prank(USER1);
        xStaking.changePowerDelegation(USER1);

        vm.prank(USER3);
        xStaking.changePowerDelegation(USER3);

        assertEq(xStaking.userPower(USER1), power1, "4: user 1 power");
        assertEq(xStaking.userPower(USER2), power2, "4: user 2 power");
        assertEq(xStaking.userPower(USER3), power3, "4: user 3 power");

        assertEq(daoToken.balanceOf(USER1), 0, "4: user 1 dao balance");
        assertEq(daoToken.balanceOf(USER2), 0, "4: user 2 dao balance");
        assertEq(daoToken.balanceOf(USER3), 0, "4: user 3 dao balance");

        // ------------------------------- User1 => User3 => User2 => User3
        vm.prank(USER1);
        xStaking.changePowerDelegation(USER3);

        vm.prank(USER3);
        xStaking.changePowerDelegation(USER2);

        vm.prank(USER2);
        xStaking.changePowerDelegation(USER3);

        assertEq(xStaking.userPower(USER1), 0, "5: user 1 power");
        assertEq(xStaking.userPower(USER2), power3, "5: user 2 power");
        assertEq(xStaking.userPower(USER3), power1 + power2, "5: user 3 power");

        assertEq(daoToken.balanceOf(USER1), 0, "5: user 1 dao balance");
        assertEq(daoToken.balanceOf(USER2), 0, "5: user 2 dao balance");
        assertEq(daoToken.balanceOf(USER3), 0, "5: user 3 dao balance");

        // ------------------------------- Deposit 2
        _mintAndDepositToStaking(USER1, power1);
        _mintAndDepositToStaking(USER2, power2);
        _mintAndDepositToStaking(USER3, power3);

        assertEq(xStaking.userPower(USER1), 0, "6: user 1 power");
        assertEq(xStaking.userPower(USER2), 2 * power3, "6: user 2 power");
        assertEq(xStaking.userPower(USER3), 2 * (power1 + power2), "6: user 3 power");

        assertEq(daoToken.balanceOf(USER1), 0, "6: user 1 dao balance");
        assertEq(daoToken.balanceOf(USER2), 2 * power3, "6: user 2 dao balance");
        assertEq(daoToken.balanceOf(USER3), 2 * (power1 + power2), "6: user 3 dao balance");

        // ------------------------------- Withdraw 1
        vm.prank(USER1);
        xStaking.withdraw(power1 * 2);

        vm.prank(USER2);
        xStaking.withdraw(power2 * 2);

        assertEq(xStaking.userPower(USER1), 0, "7: user 1 power");
        assertEq(xStaking.userPower(USER2), 2 * power3, "7: user 2 power");
        assertEq(xStaking.userPower(USER3), 0, "7: user 3 power");

        assertEq(daoToken.balanceOf(USER1), 0, "7: user 1 dao balance");
        assertEq(daoToken.balanceOf(USER2), 2 * power3, "7: user 2 dao balance");
        assertEq(daoToken.balanceOf(USER3), 0, "7: user 3 dao balance");
    }

    function testTransferXStbl() public {
        // ------------------------------- mint xSTBL and deposit to staking before upgrade
        address[] memory users = new address[](3);
        users[0] = USER1;
        users[1] = USER2;
        users[2] = USER3;

        uint power1 = 5001e18;
        uint power2 = 1002e18;
        uint power3 = 3003e18;

        // ------------------------------- Upgrade and sync
        IStabilityDaoToken daoToken = _upgradeAndSetup();

        vm.prank(multisig);
        xStaking.syncStabilityDaoTokenBalances(users);

        // ------------------------------- Deposit 1
        _mintAndDepositToStaking(USER1, power1);
        _mintAndDepositToStaking(USER2, power2);
        _mintAndDepositToStaking(USER3, power3);

        assertEq(xStaking.userPower(USER1), power1, "1: user 1 power");
        assertEq(xStaking.userPower(USER2), power2, "1: user 2 power");
        assertEq(xStaking.userPower(USER3), power3, "1: user 3 power");

        assertEq(daoToken.balanceOf(USER1), power1, "1: user 1 dao balance");
        assertEq(daoToken.balanceOf(USER2), 0, "1: user 2 dao balance");
        assertEq(daoToken.balanceOf(USER3), 0, "1: user 3 dao balance");

        assertEq(IERC20(address(xStbl)).balanceOf(USER1), 0, "1: user 1 xStbl balance");
        assertEq(IERC20(address(xStbl)).balanceOf(USER2), 0, "1: user 2 xStbl balance");
        assertEq(IERC20(address(xStbl)).balanceOf(USER3), 0, "1: user 3 xStbl balance");

        // ------------------------------- Users 1 delegates to user 2
        vm.prank(USER1);
        xStaking.changePowerDelegation(USER2);

        assertEq(xStaking.userPower(USER1), 0, "2: user 1 power");
        assertEq(xStaking.userPower(USER2), power2 + power1, "2: user 2 power");
        assertEq(xStaking.userPower(USER3), power3, "2: user 3 power");

        assertEq(daoToken.balanceOf(USER1), 0, "2: user 1 dao balance");
        assertEq(daoToken.balanceOf(USER2), power2 + power1, "2: user 2 dao balance");
        assertEq(daoToken.balanceOf(USER3), power3, "2: user 3 dao balance");
    }

    //region --------------------------------- Internal logic
    function _mintAndDepositToStaking(address user, uint amount) internal {
        deal(SonicConstantsLib.TOKEN_STBL, user, amount);

        vm.prank(user);
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(xStbl), amount);

        vm.prank(user);
        xStbl.enter(amount);

        vm.prank(user);
        IERC20(address(xStbl)).approve(address(xStaking), amount);

        vm.prank(user);
        xStaking.deposit(amount);
    }

    function _upgradeAndSetup() internal returns (IStabilityDaoToken) {
        IStabilityDaoToken stblDaoToken = _createStabilityDaoTokenInstance();
        _upgradePlatform();

        vm.prank(multisig);
        xStaking.initializeStabilityDaoToken(address(stblDaoToken));

        return stblDaoToken;
    }
    //endregion --------------------------------- Internal logic

    //region --------------------------------- Helpers
    function _upgradePlatform() internal {
        rewind(1 days);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](2);
        address[] memory implementations = new address[](2);

        proxies[0] = SonicConstantsLib.XSTBL_XSTAKING;
        proxies[1] = SonicConstantsLib.TOKEN_XSTBL;

        implementations[0] = address(new XStaking());
        implementations[1] = address(new XSTBL());

        vm.startPrank(platform.multisig());
        platform.announcePlatformUpgrade("2025.08.21-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }

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
        token.initialize(address(PLATFORM), SonicConstantsLib.TOKEN_XSTBL, SonicConstantsLib.XSTBL_XSTAKING, p);
        return token;
    }

    function _updateConfig(uint minimalPower_) internal {
        IStabilityDaoToken daoToken = IStabilityDaoToken(xStaking.stabilityDaoToken());
        IStabilityDaoToken.DaoParams memory p = daoToken.config();
        p.minimalPower = minimalPower_;

        vm.prank(multisig);
        daoToken.updateConfig(p);
    }
    //endregion --------------------------------- Helpers
}
