// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {IStabilityDAO} from "../../src/interfaces/IStabilityDAO.sol";
import {StabilityDAO} from "../../src/tokenomics/StabilityDAO.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {XSTBL} from "../../src/tokenomics/XSTBL.sol";
import {IXSTBL} from "../../src/interfaces/IXSTBL.sol";
import {IXStaking} from "../../src/interfaces/IXStaking.sol";
import {Platform} from "../../src/core/Platform.sol";

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
        IStabilityDAO stabilityDao = _upgradeAndSetup();

        vm.prank(multisig);
        xStaking.syncStabilityDAOBalances(users);

        assertEq(stabilityDao.getVotes(USER1), 5000e18, "1: user 1 power");
        assertEq(stabilityDao.getVotes(USER2), 0, "1: user 2 power");
        assertEq(stabilityDao.getVotes(USER3), 0, "1: user 3 power");

        assertEq(xStaking.balanceOf(USER1), 5000e18, "1: user 1 xStaking balance");
        assertEq(xStaking.balanceOf(USER2), 3000e18, "1: user 2 xStaking balance");
        assertEq(xStaking.balanceOf(USER3), 0, "1: user 3 xStaking balance");

        // ------------------------------- Deposit and withdraw 2
        _mintAndDepositToStaking(USER2, 1000e18);
        _mintAndDepositToStaking(USER3, 4000e18);

        vm.prank(USER1);
        xStaking.withdraw(1000e18);

        assertEq(stabilityDao.getVotes(USER1), 4000e18, "2: user 1 power");
        assertEq(stabilityDao.getVotes(USER2), 4000e18, "2: user 2 power");
        assertEq(stabilityDao.getVotes(USER3), 4000e18, "2: user 3 power");

        assertEq(xStaking.balanceOf(USER1), 4000e18, "2: user 1 xStaking balance");
        assertEq(xStaking.balanceOf(USER2), 4000e18, "2: user 2 xStaking balance");
        assertEq(xStaking.balanceOf(USER3), 4000e18, "2: user 3 xStaking balance");

        // ------------------------------- Deposit and withdraw 3
        _mintAndDepositToStaking(USER2, 1000e18);
        _mintAndDepositToStaking(USER3, 1000e18);

        vm.prank(USER1);
        xStaking.withdraw(1000e18);

        assertEq(stabilityDao.getVotes(USER1), 0, "3: user 1 power");
        assertEq(stabilityDao.getVotes(USER2), 5000e18, "3: user 2 power");
        assertEq(stabilityDao.getVotes(USER3), 5000e18, "3: user 3 power");

        assertEq(xStaking.balanceOf(USER1), 3000e18, "3: user 1 xStaking balance");
        assertEq(xStaking.balanceOf(USER2), 5000e18, "3: user 2 xStaking balance");
        assertEq(xStaking.balanceOf(USER3), 5000e18, "3: user 3 xStaking balance");

        // ------------------------------- Deposit and withdraw 4
        _mintAndDepositToStaking(USER1, 5000e18);

        vm.prank(USER2);
        xStaking.withdraw(5000e18);

        vm.prank(USER3);
        xStaking.withdraw(1500e18);

        assertEq(stabilityDao.getVotes(USER1), 8000e18, "4: user 1 power");
        assertEq(stabilityDao.getVotes(USER2), 0, "4: user 2 power");
        assertEq(stabilityDao.getVotes(USER3), 0, "4: user 3 power");

        assertEq(xStaking.balanceOf(USER1), 8000e18, "4: user 1 xStaking balance");
        assertEq(xStaking.balanceOf(USER2), 0, "4: user 2 xStaking balance");
        assertEq(xStaking.balanceOf(USER3), 3500e18, "4: user 3 xStaking balance");
    }

    function testDelegation() public {
        // ------------------------------- mint xSTBL and deposit to staking before upgrade
        address[] memory users = new address[](3);
        users[0] = USER1;
        users[1] = USER2;
        users[2] = USER3;

        uint balance1 = 1001e18;
        uint balance2 = 2002e18;
        uint balance3 = 3003e18;

        // ------------------------------- Upgrade and sync
        IStabilityDAO stabilityDao = _upgradeAndSetup();
        assertEq(stabilityDao.minimalPower(), 4000e18, "initial minimal power is very high");

        vm.prank(multisig);
        xStaking.syncStabilityDAOBalances(users);

        // ------------------------------- Deposit 1
        _mintAndDepositToStaking(USER1, balance1);
        _mintAndDepositToStaking(USER2, balance2);
        _mintAndDepositToStaking(USER3, balance3);

        assertEq(xStaking.balanceOf(USER1), balance1, "1: user 1 xStaking balance");
        assertEq(xStaking.balanceOf(USER2), balance2, "1: user 2 xStaking balance");
        assertEq(xStaking.balanceOf(USER3), balance3, "1: user 3 xStaking balance");

        assertEq(stabilityDao.getVotes(USER1), 0, "1: user 1 power");
        assertEq(stabilityDao.getVotes(USER2), 0, "1: user 2 power");
        assertEq(stabilityDao.getVotes(USER3), 0, "1: user 3 power");

        // ------------------------------- Users 1 and 3 delegate to user 2
        vm.prank(USER1);
        stabilityDao.setPowerDelegation(USER2);

        vm.prank(USER3);
        stabilityDao.setPowerDelegation(USER2);

        // ------------------------------- Threshold is too high, users don't have any power
        assertEq(stabilityDao.getVotes(USER1), 0, "2: user 1 power");
        assertEq(stabilityDao.getVotes(USER2), 0, "2: user 2 power");
        assertEq(stabilityDao.getVotes(USER3), 0, "2: user 3 power");

        assertEq(xStaking.balanceOf(USER1), balance1, "2: user 1 xStaking balance");
        assertEq(xStaking.balanceOf(USER2), balance2, "2: user 2 xStaking balance");
        assertEq(xStaking.balanceOf(USER3), balance3, "2: user 3 xStaking balance");

        // ------------------------------- Reduce threshold 4000 => 1000 and sync
        _updateMinimalPower(1000e18);
        vm.prank(multisig);
        xStaking.syncStabilityDAOBalances(users);

        // ------------------------------- Now user 2 has all power because users 1 and 3 have delegated him their powers
        assertEq(stabilityDao.getVotes(USER1), 0, "2: user 1 power");
        assertEq(stabilityDao.getVotes(USER2), balance2 + balance1 + balance3, "2: user 2 power");
        assertEq(stabilityDao.getVotes(USER3), 0, "2: user 3 power");

        assertEq(xStaking.balanceOf(USER1), balance1, "2: user 1 xStaking balance");
        assertEq(xStaking.balanceOf(USER2), balance2, "2: user 2 xStaking balance");
        assertEq(xStaking.balanceOf(USER3), balance3, "2: user 3 xStaking balance");

        // ------------------------------- Clear delegation
        vm.prank(USER1);
        stabilityDao.setPowerDelegation(USER1);

        vm.prank(USER3);
        stabilityDao.setPowerDelegation(USER3);

        assertEq(stabilityDao.getVotes(USER1), balance1, "4: user 1 power");
        assertEq(stabilityDao.getVotes(USER2), balance2, "4: user 2 power");
        assertEq(stabilityDao.getVotes(USER3), balance3, "4: user 3 power");

        assertEq(xStaking.balanceOf(USER1), balance1, "4: user 1 xStaking balance");
        assertEq(xStaking.balanceOf(USER2), balance2, "4: user 2 xStaking balance");
        assertEq(xStaking.balanceOf(USER3), balance3, "4: user 3 xStaking balance");

        // ------------------------------- User1 => User3 => User2 => User3
        vm.prank(USER1);
        stabilityDao.setPowerDelegation(USER3);

        vm.prank(USER3);
        stabilityDao.setPowerDelegation(USER2);

        vm.prank(USER2);
        stabilityDao.setPowerDelegation(USER3);

        assertEq(stabilityDao.getVotes(USER1), 0, "5: user 1 power");
        assertEq(stabilityDao.getVotes(USER2), balance3, "5: user 2 power");
        assertEq(stabilityDao.getVotes(USER3), balance1 + balance2, "5: user 3 power");

        assertEq(xStaking.balanceOf(USER1), balance1, "5: user 1 xStaking balance");
        assertEq(xStaking.balanceOf(USER2), balance2, "5: user 2 xStaking balance");
        assertEq(xStaking.balanceOf(USER3), balance3, "5: user 3 xStaking balance");

        // ------------------------------- Deposit 2
        _mintAndDepositToStaking(USER1, balance1);
        _mintAndDepositToStaking(USER2, balance2);
        _mintAndDepositToStaking(USER3, balance3);

        assertEq(stabilityDao.getVotes(USER1), 0, "6: user 1 power");
        assertEq(stabilityDao.getVotes(USER2), 2 * balance3, "6: user 2 power");
        assertEq(stabilityDao.getVotes(USER3), 2 * (balance1 + balance2), "6: user 3 power");

        assertEq(xStaking.balanceOf(USER1), 2 * balance1, "6: user 1 xStaking balance");
        assertEq(xStaking.balanceOf(USER2), 2 * balance2, "6: user 2 xStaking balance");
        assertEq(xStaking.balanceOf(USER3), 2 * balance3, "6: user 3 xStaking balance");

        // ------------------------------- Withdraw 1
        vm.prank(USER1);
        xStaking.withdraw(balance1 * 2);

        vm.prank(USER2);
        xStaking.withdraw(balance2 * 2);

        assertEq(stabilityDao.getVotes(USER1), 0, "7: user 1 power");
        assertEq(stabilityDao.getVotes(USER2), 2 * balance3, "7: user 2 power");
        assertEq(stabilityDao.getVotes(USER3), 0, "7: user 3 power");

        assertEq(xStaking.balanceOf(USER1), 0, "7: user 1 xStaking balance");
        assertEq(xStaking.balanceOf(USER2), 0, "7: user 2 xStaking balance");
        assertEq(xStaking.balanceOf(USER3), 2 * balance3, "7: user 3 xStaking balance");
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

    function _upgradeAndSetup() internal returns (IStabilityDAO) {
        IStabilityDAO stblDaoToken = _createStabilityDAOInstance();
        _upgradePlatform();

        vm.prank(multisig);
        IPlatform(PLATFORM).setupStabilityDAO(address(stblDaoToken));

        return stblDaoToken;
    }

    //endregion --------------------------------- Internal logic

    //region --------------------------------- Helpers
    function _upgradePlatform() internal {
        rewind(1 days);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](3);
        address[] memory implementations = new address[](3);

        proxies[0] = SonicConstantsLib.XSTBL_XSTAKING;
        proxies[1] = SonicConstantsLib.TOKEN_XSTBL;
        proxies[2] = SonicConstantsLib.PLATFORM;

        implementations[0] = address(new XStaking());
        implementations[1] = address(new XSTBL());
        implementations[2] = address(new Platform());

        vm.startPrank(platform.multisig());
        platform.announcePlatformUpgrade("2025.08.21-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }

    function _createStabilityDAOInstance() internal returns (IStabilityDAO) {
        IStabilityDAO.DaoParams memory p = IStabilityDAO.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 50_00,
            proposalThreshold: 10_000,
            quorum: 20_000,
            powerAllocationDelay: 86400
        });

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new StabilityDAO()));
        IStabilityDAO token = IStabilityDAO(address(proxy));
        token.initialize(address(PLATFORM), SonicConstantsLib.TOKEN_XSTBL, SonicConstantsLib.XSTBL_XSTAKING, p);
        return token;
    }

    function _updateMinimalPower(uint minimalPower_) internal {
        IPlatform platform = IPlatform(PLATFORM);
        IStabilityDAO daoToken = IStabilityDAO(platform.stabilityDAO());
        IStabilityDAO.DaoParams memory p = daoToken.config();
        p.minimalPower = minimalPower_;

        vm.prank(platform.multisig());
        daoToken.updateConfig(p);
    }
    //endregion --------------------------------- Helpers
}
