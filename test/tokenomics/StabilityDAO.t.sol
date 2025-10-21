// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IStabilityDAO} from "../../src/interfaces/IStabilityDAO.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Test} from "forge-std/Test.sol";
import {StabilityDAO} from "../../src/tokenomics/StabilityDAO.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StabilityDAOSonicTest is Test {
    using SafeERC20 for IERC20;

    uint public constant FORK_BLOCK = 47854805; // Sep-23-2025 04:02:39 AM +UTC
    address internal multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();

        console.logBytes32(
            keccak256(abi.encode(uint(keccak256("erc7201:stability.StabilityDAO")) - 1)) & ~bytes32(uint(0xff))
        );
    }

    //region --------------------------------- Unit tests

    function testInitializeAndView() public {
        IStabilityDAO.DaoParams memory p = IStabilityDAO.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 50_00,
            quorum: 20_00,
            proposalThreshold: 10_00,
            powerAllocationDelay: 86400
        });

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new StabilityDAO()));

        IStabilityDAO token = IStabilityDAO(address(proxy));
        token.initialize(SonicConstantsLib.PLATFORM, address(1), address(2), p);

        assertEq(token.xStbl(), address(1));
        assertEq(token.xStaking(), address(2));
        assertEq(token.name(), "Stability DAO");
        assertEq(token.symbol(), "STBLDAO");
        assertEq(token.decimals(), 18);

        assertEq(token.minimalPower(), p.minimalPower);
        assertEq(token.exitPenalty(), p.exitPenalty);
        assertEq(token.proposalThreshold(), p.proposalThreshold);
        assertEq(token.powerAllocationDelay(), p.powerAllocationDelay);
    }

    function testMintBurn() public {
        IStabilityDAO token = _createStabilityDAOInstance();

        vm.prank(address(0x123));
        vm.expectRevert(IControllable.IncorrectMsgSender.selector);
        token.mint(address(0x123), 1e18);

        vm.prank(address(0x123));
        vm.expectRevert(IControllable.IncorrectMsgSender.selector);
        token.burn(address(0x123), 1e18);

        vm.prank(multisig);
        vm.expectRevert(IControllable.IncorrectMsgSender.selector);
        token.mint(address(0x123), 1e18);

        vm.prank(multisig);
        vm.expectRevert(IControllable.IncorrectMsgSender.selector);
        token.burn(address(0x123), 1e18);

        vm.prank(token.xStaking());
        token.mint(address(0x123), 1e18);
        assertEq(token.balanceOf(address(0x123)), 1e18);

        vm.prank(token.xStaking());
        token.burn(address(0x123), 0.5e18);
        assertEq(token.balanceOf(address(0x123)), 0.5e18);

        vm.prank(token.xStaking());
        token.burn(address(0x123), 0.5e18);
        assertEq(token.balanceOf(address(0x123)), 0);
    }

    function testUpdateConfig() public {
        IStabilityDAO token = _createStabilityDAOInstance();

        vm.prank(multisig);
        IPlatform(SonicConstantsLib.PLATFORM).setupStabilityDAO(address(token));

        IStabilityDAO.DaoParams memory p1 = IStabilityDAO.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 50_00, // 50%
            proposalThreshold: 10_00, // 10%
            quorum: 20_00, // 20%
            powerAllocationDelay: 86400
        });

        IStabilityDAO.DaoParams memory p2 = IStabilityDAO.DaoParams({
            minimalPower: 5000e18,
            exitPenalty: 80_00, // 80%
            proposalThreshold: 20_00, // 20%
            quorum: 35_00, // 35%
            powerAllocationDelay: 172800
        });

        IStabilityDAO.DaoParams memory config = token.config();
        assertEq(config.minimalPower, p1.minimalPower);
        assertEq(config.exitPenalty, p1.exitPenalty);
        assertEq(config.proposalThreshold, p1.proposalThreshold);
        assertEq(config.powerAllocationDelay, p1.powerAllocationDelay);

        vm.prank(address(0x123));
        vm.expectRevert(IControllable.NotMultisig.selector);
        token.updateConfig(p2);

        vm.prank(token.xStaking());
        vm.expectRevert(IControllable.NotMultisig.selector);
        token.updateConfig(p2);

        config = _updateConfig(token, multisig, p2);

        assertEq(config.minimalPower, p2.minimalPower);
        assertEq(config.exitPenalty, p2.exitPenalty);
        assertEq(config.proposalThreshold, p2.proposalThreshold);
        assertEq(config.powerAllocationDelay, p2.powerAllocationDelay);

        config = _updateConfig(token, IPlatform(SonicConstantsLib.PLATFORM).governance(), p2);

        assertEq(config.minimalPower, p2.minimalPower);
        assertEq(config.exitPenalty, p2.exitPenalty);
        assertEq(config.proposalThreshold, p2.proposalThreshold);
        assertEq(config.powerAllocationDelay, p2.powerAllocationDelay);
    }

    function testNonTransferable() public {
        IStabilityDAO token = _createStabilityDAOInstance();

        vm.prank(token.xStaking());
        token.mint(address(0x123), 1e18);

        vm.prank(address(0x123));
        vm.expectRevert(StabilityDAO.NonTransferable.selector);
        token.transfer(address(0x456), 1e18);

        vm.prank(address(0x123));
        token.approve(address(0x456), 1e18);

        vm.prank(address(0x456));
        vm.expectRevert(StabilityDAO.NonTransferable.selector);
        token.transferFrom(address(0x123), address(0x789), 1e18);
    }

// todo
//    function testPowerDelegation() public {
//        address[3] memory users = [address(1), address(2), address(3)];
//        uint72[3] memory amounts = [100e18, 150e18, 300e18];
//
//        // ------------------------------- mint xSTBL and deposit to staking
//        for (uint i; i < users.length; ++i) {
//            tokenA.mint(amounts[i]);
//            IERC20(address(tokenA)).safeTransfer(users[i], amounts[i]);
//
//            vm.prank(users[i]);
//            IERC20(stbl).approve(address(xStbl), amounts[i]);
//
//            vm.prank(users[i]);
//            xStbl.enter(amounts[i]);
//        }
//
//        // ------------------------------- Each user deposits half of their xSTBL to staking
//        for (uint i; i < users.length; ++i) {
//            vm.prank(users[i]);
//            IERC20(address(xStbl)).approve(address(xStaking), amounts[i]);
//
//            vm.prank(users[i]);
//            xStaking.deposit(amounts[i] / 2);
//
//            assertEq(xStaking.balanceOf(users[i]), amounts[i] / 2);
//            assertEq(xStaking.userPower(users[i]), amounts[i] / 2);
//        }
//
//        // ------------------------------- Initialize dao token
//        vm.expectRevert(XStaking.StblDaoNotInitialized.selector);
//        vm.prank(users[0]);
//        xStaking.changePowerDelegation(users[1]);
//
//        vm.prank(platform.multisig());
//        xStaking.initializeStabilityDAO(address(new MockStabilityDAO()));
//
//        // ------------------------------- 1: 0 => 1
//        vm.prank(users[0]);
//        xStaking.changePowerDelegation(users[2]);
//
//        vm.expectRevert(XStaking.AlreadyDelegated.selector);
//        vm.prank(users[0]);
//        xStaking.changePowerDelegation(users[2]);
//
//        vm.prank(users[0]);
//        xStaking.changePowerDelegation(users[0]);
//
//        vm.prank(users[0]);
//        xStaking.changePowerDelegation(users[1]);
//
//        assertEq(xStaking.userPower(users[0]), 0, "1: User 0 has delegates his power to user 1");
//        assertEq(
//            xStaking.userPower(users[1]),
//            amounts[1] / 2 + amounts[0] / 2,
//            "1: balance user 1 + delegated power of user 0"
//        );
//        assertEq(xStaking.userPower(users[2]), amounts[2] / 2, "1: balance user 2");
//
//        // ------------------------------- 2: 1 => 2
//        vm.prank(users[1]);
//        xStaking.changePowerDelegation(users[2]);
//
//        assertEq(xStaking.userPower(users[0]), 0, "2: User 0 has delegates his power to user 1");
//        assertEq(xStaking.userPower(users[1]), amounts[0] / 2, "2: delegated power of user 0");
//        assertEq(
//            xStaking.userPower(users[2]),
//            amounts[2] / 2 + amounts[1] / 2,
//            "2: balance user 2 + delegated power of user 1"
//        );
//
//        // ------------------------------- 3: 2 => 0
//        vm.prank(users[2]);
//        xStaking.changePowerDelegation(users[0]);
//
//        assertEq(xStaking.userPower(users[0]), amounts[2] / 2, "3: delegated power of user 2");
//        assertEq(xStaking.userPower(users[1]), amounts[0] / 2, "3: delegated power of user 0");
//        assertEq(xStaking.userPower(users[2]), amounts[1] / 2, "3: delegated power of user 1");
//
//        // ------------------------------- 4: Each user deposits second half of their xSTBL to staking
//        for (uint i; i < users.length; ++i) {
//            vm.prank(users[i]);
//            xStaking.deposit(amounts[i] / 2);
//
//            assertEq(xStaking.balanceOf(users[i]), amounts[i], "full balance");
//        }
//
//        assertEq(xStaking.userPower(users[0]), amounts[2], "4: delegated power of user 2");
//        assertEq(xStaking.userPower(users[1]), amounts[0], "4: delegated power of user 0");
//        assertEq(xStaking.userPower(users[2]), amounts[1], "4: delegated power of user 1");
//
//        // ------------------------------- 5: User 1 withdraws half of his stake
//        vm.prank(users[1]);
//        xStaking.withdraw(amounts[1] / 2);
//
//        assertEq(xStaking.userPower(users[0]), amounts[2], "5: delegated power of user 2");
//        assertEq(xStaking.userPower(users[1]), amounts[0], "5: delegated power of user 0");
//        assertEq(xStaking.userPower(users[2]), amounts[1] / 2, "5: delegated power of user 1");
//
//        // ------------------------------- 6: User 1 removes delegation
//        vm.prank(users[1]);
//        xStaking.changePowerDelegation(users[1]);
//
//        assertEq(xStaking.userPower(users[0]), amounts[2], "6: delegated power of user 2");
//        assertEq(xStaking.userPower(users[1]), amounts[1] / 2 + amounts[0], "6: delegated power of user 0");
//        assertEq(xStaking.userPower(users[2]), 0, "6: all power was delegated to user 0");
//
//        {
//            (address delegatedTo, address[] memory delegatedFrom) = xStaking.delegates(users[0]);
//            assertEq(delegatedTo, users[1], "6: user 0 has delegated his power to user 1");
//            assertEq(delegatedFrom.length, 1, "6: single user (2) has delegated to user 0");
//            assertEq(delegatedFrom[0], users[2], "6: user 2 has delegated to user 0");
//        }
//
//        {
//            (address delegatedTo, address[] memory delegatedFrom) = xStaking.delegates(users[1]);
//            assertEq(delegatedTo, address(0), "6: user 1 has not delegated power");
//            assertEq(delegatedFrom.length, 1, "6: single user (0) has delegated to user 1");
//            assertEq(delegatedFrom[0], users[0], "6: user 0 has delegated to user 1");
//        }
//
//        {
//            (address delegatedTo, address[] memory delegatedFrom) = xStaking.delegates(users[2]);
//            assertEq(delegatedTo, users[0], "6: user 2 has delegated his power to user 0");
//            assertEq(delegatedFrom.length, 0, "6: no one has delegated to user 2");
//        }
//
//        // ------------------------------- 7: Users 0 and 2 remove delegations
//        vm.prank(users[0]);
//        xStaking.changePowerDelegation(users[0]); // remove using delegation to oneself
//
//        vm.prank(users[2]);
//        xStaking.changePowerDelegation(address(0)); // remove using zero address
//
//        assertEq(xStaking.userPower(users[0]), amounts[0], "7: user 0 has not delegated power");
//        assertEq(xStaking.userPower(users[1]), amounts[1] / 2, "7: user 1 has not delegated power");
//        assertEq(xStaking.userPower(users[2]), amounts[2], "7: user 2 has not delegated power");
//    }


    //endregion --------------------------------- Unit tests

    //region --------------------------------- Utils
    function _updateConfig(IStabilityDAO token, address user, IStabilityDAO.DaoParams memory p2) internal returns (IStabilityDAO.DaoParams memory) {
        uint snapshot = vm.snapshotState();
        vm.prank(IPlatform(SonicConstantsLib.PLATFORM).governance());
        token.updateConfig(p2);
        vm.revertToState(snapshot);

        vm.prank(multisig);
        token.updateConfig(p2);

        return token.config();
    }

    function _createStabilityDAOInstance() internal returns (IStabilityDAO) {
        IStabilityDAO.DaoParams memory p = IStabilityDAO.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 80_00,
            quorum: 15_00,
            proposalThreshold: 25_00,
        powerAllocationDelay : 86400
        });

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new StabilityDAO()));
        IStabilityDAO token = IStabilityDAO(address(proxy));
        token.initialize(SonicConstantsLib.PLATFORM, SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.XSTBL_XSTAKING, p);
        return token;
    }
    //endregion --------------------------------- Utils
}
