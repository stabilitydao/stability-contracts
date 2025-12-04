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
import {DAO} from "../../src/tokenomics/DAO.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Platform} from "../../src/core/Platform.sol";
import {PriceAggregatorOApp} from "../../src/periphery/PriceAggregatorOApp.sol";

contract DAOSonicTest is Test {
    using SafeERC20 for IERC20;

    uint public constant FORK_BLOCK = 47854805; // Sep-23-2025 04:02:39 AM +UTC
    address internal multisig;

    struct Powers {
        uint localPower;
        uint otherPower;
        uint delegatedLocalPower;
        uint delegatedOtherPower;
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();
        _upgradePlatform();

        //        console.logBytes32(
        //            keccak256(abi.encode(uint(keccak256("erc7201:stability.StabilityDAO")) - 1)) & ~bytes32(uint(0xff))
        //        );
    }

    //region --------------------------------- Unit tests

    function testInitializeAndView() public {
        IStabilityDAO.DaoParams memory p = IStabilityDAO.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 50_00,
            quorum: 20_000,
            proposalThreshold: 10_000,
            powerAllocationDelay: 86400
        });

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new DAO()));

        IStabilityDAO token = IStabilityDAO(address(proxy));
        token.initialize(SonicConstantsLib.PLATFORM, address(1), address(2), p, "Stability DAO", "STBL_DAO");

        assertEq(token.xStbl(), address(1));
        assertEq(token.xStaking(), address(2));
        assertEq(token.name(), "Stability DAO");
        assertEq(token.symbol(), "STBL_DAO");
        assertEq(token.decimals(), 18);

        assertEq(token.minimalPower(), p.minimalPower);
        assertEq(token.exitPenalty(), p.exitPenalty);
        assertEq(token.proposalThreshold(), p.proposalThreshold);
        assertEq(token.powerAllocationDelay(), p.powerAllocationDelay);
        assertEq(token.quorum(), p.quorum);
    }

    function testMintBurn() public {
        address governance = IPlatform(SonicConstantsLib.PLATFORM).governance();
        IStabilityDAO token = _createDAOInstance();

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

        vm.prank(governance);
        vm.expectRevert(IControllable.IncorrectMsgSender.selector);
        token.mint(address(0x123), 1e18);

        vm.prank(governance);
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
        IStabilityDAO.DaoParams memory p1 = IStabilityDAO.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 50_00, // 50%
            quorum: 20_000, // 20%
            proposalThreshold: 10_000, // 10%
            powerAllocationDelay: 86400
        });

        IStabilityDAO.DaoParams memory p2 = IStabilityDAO.DaoParams({
            minimalPower: 5000e18,
            exitPenalty: 80_00, // 80%
            quorum: 35_000, // 35%
            proposalThreshold: 20_000, // 20%
            powerAllocationDelay: 172800
        });

        IStabilityDAO token = _createDAOInstance(p1);

        vm.prank(multisig);
        IPlatform(SonicConstantsLib.PLATFORM).setupStabilityDAO(address(token));

        IStabilityDAO.DaoParams memory config = token.config();
        assertEq(config.minimalPower, p1.minimalPower, "minimalPower");
        assertEq(config.exitPenalty, p1.exitPenalty, "exitPenalty");
        assertEq(config.proposalThreshold, p1.proposalThreshold, "proposalThreshold");
        assertEq(config.powerAllocationDelay, p1.powerAllocationDelay, "powerAllocationDelay");
        assertEq(config.quorum, p1.quorum, "quorum");

        vm.prank(address(0x123));
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        token.updateConfig(p2);

        vm.prank(token.xStaking());
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        token.updateConfig(p2);

        config = _updateConfig(token, multisig, p2);

        assertEq(config.minimalPower, p2.minimalPower, "minimalPower2");
        assertEq(config.exitPenalty, p2.exitPenalty, "exitPenalty2");
        assertEq(config.proposalThreshold, p2.proposalThreshold, "proposalThreshold2");
        assertEq(config.powerAllocationDelay, p2.powerAllocationDelay, "powerAllocationDelay2");
        assertEq(config.quorum, p2.quorum, "quorum2");

        config = _updateConfig(token, IPlatform(SonicConstantsLib.PLATFORM).governance(), p2);

        assertEq(config.minimalPower, p2.minimalPower, "minimalPower3");
        assertEq(config.exitPenalty, p2.exitPenalty, "exitPenalty3");
        assertEq(config.proposalThreshold, p2.proposalThreshold, "proposalThreshold3");
        assertEq(config.powerAllocationDelay, p2.powerAllocationDelay, "powerAllocationDelay3");
        assertEq(config.quorum, p2.quorum, "quorum3");
    }

    function testUpdateConfigBadPaths() public {
        IStabilityDAO.DaoParams memory p1 = IStabilityDAO.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 50_00, // 50%
            quorum: 20_000, // 20%
            proposalThreshold: 10_000, // 10%
            powerAllocationDelay: 86400
        });
        IStabilityDAO token = _createDAOInstance(p1);

        p1.proposalThreshold = 100_000; // 100%

        vm.prank(multisig);
        vm.expectRevert(DAO.WrongValue.selector);
        token.updateConfig(p1);

        p1.proposalThreshold = 10_000;
        p1.exitPenalty = 100_00; // 100%

        vm.prank(multisig);
        vm.expectRevert(DAO.WrongValue.selector);
        token.updateConfig(p1);

        p1.exitPenalty = 50_00;
        p1.quorum = 100_000; // 100%

        vm.prank(multisig);
        vm.expectRevert(DAO.WrongValue.selector);
        token.updateConfig(p1);
    }

    function testNonTransferable() public {
        IStabilityDAO token = _createDAOInstance();

        vm.prank(token.xStaking());
        token.mint(address(0x123), 1e18);

        vm.prank(address(0x123));
        vm.expectRevert(DAO.NonTransferable.selector);
        // slither-disable-next-line erc20-unchecked-transfer
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transfer(address(0x456), 1e18);

        vm.prank(address(0x123));
        token.approve(address(0x456), 1e18);

        vm.prank(address(0x456));
        vm.expectRevert(DAO.NonTransferable.selector);
        // slither-disable-next-line erc20-unchecked-transfer
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transferFrom(address(0x123), address(0x789), 1e18);
    }

    function testSetPowerDelegation() public {
        address user1 = address(1);
        address user2 = address(2);
        IStabilityDAO dao = _createDAOInstance();

        // ---------------------------- Initial state
        vm.prank(dao.xStaking());
        dao.mint(user1, 10_000e18);

        vm.prank(dao.xStaking());
        dao.mint(user2, 20_000e18);

        assertEq(dao.getVotes(user1), 10_000e18);
        assertEq(dao.getVotes(user2), 20_000e18);

        (address delegatedTo, address[] memory delegates) = dao.delegates(user1);
        assertEq(delegatedTo, address(0));
        assertEq(delegates.length, 0);

        // ---------------------------- User 1 delegates to User 2
        vm.prank(user1);
        dao.setPowerDelegation(user2);

        vm.expectRevert(DAO.AlreadyDelegated.selector);
        vm.prank(user1);
        dao.setPowerDelegation(address(this));

        assertEq(dao.getVotes(user1), 0);
        assertEq(dao.getVotes(user2), 20_000e18 + 10_000e18);

        (delegatedTo, delegates) = dao.delegates(user1);
        assertEq(delegatedTo, user2);
        assertEq(delegates.length, 0);

        (delegatedTo, delegates) = dao.delegates(user2);
        assertEq(delegatedTo, address(0));
        assertEq(delegates.length, 1);
        assertEq(delegates[0], user1);

        // ---------------------------- User 2 delegates to User 1
        vm.prank(user2);
        dao.setPowerDelegation(user1);

        assertEq(dao.getVotes(user1), 20_000e18);
        assertEq(dao.getVotes(user2), 10_000e18);

        (delegatedTo, delegates) = dao.delegates(user1);
        assertEq(delegatedTo, user2);
        assertEq(delegates.length, 1);
        assertEq(delegates[0], user2);

        (delegatedTo, delegates) = dao.delegates(user2);
        assertEq(delegatedTo, user1);
        assertEq(delegates.length, 1);
        assertEq(delegates[0], user1);

        // ---------------------------- Both Users clear delegations
        vm.prank(user1);
        dao.setPowerDelegation(user1);

        vm.prank(user2);
        dao.setPowerDelegation(address(0));

        assertEq(dao.getVotes(user1), 10_000e18);
        assertEq(dao.getVotes(user2), 20_000e18);

        (delegatedTo, delegates) = dao.delegates(user1);
        assertEq(delegatedTo, address(0));
        assertEq(delegates.length, 0);

        (delegatedTo, delegates) = dao.delegates(user2);
        assertEq(delegatedTo, address(0));
        assertEq(delegates.length, 0);
    }

    function testDelegationForbidden() public {
        IStabilityDAO token = _createDAOInstance();

        // ---------------------- initially user delegates power to other user
        assertEq(token.delegationForbidden(), false, "delegation is allowed initially");

        address user2 = makeAddr("to");

        token.setPowerDelegation(user2);

        {
            (address delegatedTo,) = token.delegates(address(this));
            assertEq(delegatedTo, user2, "delegated to 1");
        }

        // ---------------------- Forbid delegation
        vm.prank(multisig);
        token.setDelegationForbidden(true);

        assertEq(token.delegationForbidden(), true, "delegation is forbidden now");

        // ---------------------- User is not able to re-delegate power to another user
        vm.expectRevert(DAO.DelegationForbiddenOnTheChain.selector);
        token.setPowerDelegation(makeAddr("to2"));

        {
            (address delegatedTo,) = token.delegates(address(this));
            assertEq(delegatedTo, user2, "delegated to 2");
        }

        // ---------------------- User is able to clear exist delegation
        token.setPowerDelegation(address(0));
        {
            (address delegatedTo,) = token.delegates(address(this));
            assertEq(delegatedTo, address(0), "delegated to 3");
        }
    }

    // solidity
    function testWhitelistedForOtherChainsPowers() public {
        IStabilityDAO token = _createDAOInstance();
        address user = address(0x123);

        assertEq(token.isWhitelistedForOtherChainsPowers(user), false, "initially not whitelisted");

        vm.prank(address(0x456));
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        token.setWhitelistedForOtherChainsPowers(user, true);

        vm.prank(multisig);
        token.setWhitelistedForOtherChainsPowers(user, true);
        assertEq(token.isWhitelistedForOtherChainsPowers(user), true, "whitelisted by multisig");

        vm.prank(multisig);
        token.setWhitelistedForOtherChainsPowers(user, false);
        assertEq(token.isWhitelistedForOtherChainsPowers(user), false, "removed by multisig");
    }

    // solidity
    function testUpdateOtherChainsPowers() public {
        IStabilityDAO token = _createDAOInstance();

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        uint blockTimestamp = block.timestamp;

        // -------------------------- provide powers for user 1 and user 2 on main chain
        deal(address(token), user1, 150e18);
        deal(address(token), user2, 250e18);

        // -------------------------- set power on other chains for user 1 and user 2
        {
            address[] memory users = new address[](2);
            users[0] = user1;
            users[1] = user2;
            uint[] memory powers = new uint[](2);
            powers[0] = 1000e18;
            powers[1] = 2000e18;

            vm.prank(user1);
            vm.expectRevert(DAO.NotOtherChainsPowersWhitelisted.selector);
            token.updateOtherChainsPowers(users, powers);
            skip(1); // in next tx we should have different timestamp because it's used as an epoch counter inside token

            vm.prank(multisig);
            token.setWhitelistedForOtherChainsPowers(user1, true);
            assertEq(token.isWhitelistedForOtherChainsPowers(user1), true, "user1 is whitelisted");

            blockTimestamp = block.timestamp;
            vm.prank(user1);
            token.updateOtherChainsPowers(users, powers);

            // ensure that we cannot call updateOtherChainsPowers on the same block
            vm.expectRevert(DAO.WrongValue.selector);
            vm.prank(user1);
            token.updateOtherChainsPowers(users, powers);

            skip(1); // in next tx we should have different timestamp because it's used as an epoch counter inside token
        }

        // -------------------------- check results
        {
            (uint timestamp, address[] memory users, uint[] memory powers) = token.getOtherChainsPowers();
            assertEq(timestamp, blockTimestamp, "timestamp");
            assertEq(users.length, 2, "users length");
            assertEq(powers.length, 2, "powers length");
            assertEq(users[0], user1, "user1 address");
            assertEq(users[1], user2, "user2 address");
            assertEq(powers[0], 1000e18, "user1 power");
            assertEq(powers[1], 2000e18, "user2 power");
        }

        // -------------------------- set power on other chains for user 3
        {
            address[] memory users = new address[](1);
            users[0] = user3;
            uint[] memory powers = new uint[](1);
            powers[0] = 3000e18;

            blockTimestamp = block.timestamp;
            vm.prank(user1);
            token.updateOtherChainsPowers(users, powers);
            skip(1); // in next tx we should have different timestamp because it's used as an epoch counter inside token
        }

        // -------------------------- check results
        {
            (uint timestamp, address[] memory users, uint[] memory powers) = token.getOtherChainsPowers();
            assertEq(timestamp, blockTimestamp, "timestamp");
            assertEq(users.length, 1, "users length");
            assertEq(powers.length, 1, "powers length");
            assertEq(users[0], user3, "user3 address");
            assertEq(powers[0], 3000e18, "user3 power");
        }
    }

    function testGetVotesPower() public {
        IStabilityDAO token = _createDAOInstance();

        address user1 = makeAddr("user1");
        address user2 = address(0x2);
        address user3 = makeAddr("user3");

        // -------------------------- provide powers for user 1 and user 2 on main chain
        deal(address(token), user1, 150e18);
        deal(address(token), user2, 250e18);

        // -------------------------- set power on other chains for user 1 and user 2
        {
            address[] memory users = new address[](2);
            users[0] = user1;
            users[1] = user2;
            uint[] memory powers = new uint[](2);
            powers[0] = 1000e18;
            powers[1] = 2000e18;

            vm.prank(user1);
            vm.expectRevert(DAO.NotOtherChainsPowersWhitelisted.selector);
            token.updateOtherChainsPowers(users, powers);
            skip(1); // in next tx we should have different timestamp because it's used as an epoch counter inside token

            vm.prank(multisig);
            token.setWhitelistedForOtherChainsPowers(user1, true);
            assertEq(token.isWhitelistedForOtherChainsPowers(user1), true, "user1 is whitelisted");

            vm.prank(user1);
            token.updateOtherChainsPowers(users, powers);
            skip(1); // in next tx we should have different timestamp because it's used as an epoch counter inside token
        }

        // -------------------------- check initial vote powers
        {
            assertEq(token.getVotes(user1), 150e18 + 1000e18, "1: getVotes user 1");
            assertEq(token.getVotes(user2), 250e18 + 2000e18, "1: getVotes user 2");

            Powers memory p1 = _getPowers(token, user1);
            assertEq(p1.localPower, 150e18, "1: local power of user 1");
            assertEq(p1.otherPower, 1000e18, "1: other power of user 1");
            assertEq(p1.delegatedLocalPower, 0, "1: delegated local power of user 1");
            assertEq(p1.delegatedOtherPower, 0, "1: delegated other power of user 1");

            Powers memory p2 = _getPowers(token, user2);
            assertEq(p2.localPower, 250e18, "1: local power of user 2");
            assertEq(p2.otherPower, 2000e18, "1: other power of user 2");
            assertEq(p2.delegatedLocalPower, 0, "1: delegated local power of user 2");
            assertEq(p2.delegatedOtherPower, 0, "1: delegated other power of user 2");
        }

        // -------------------------- user 1 delegates his power to user 2
        vm.prank(user1);
        token.setPowerDelegation(user2);

        {
            assertEq(token.getVotes(user1), 0, "2: getVotes user 1");
            assertEq(token.getVotes(user2), 250e18 + 2000e18 + 150e18 + 1000e18, "2: getVotes user 2");

            Powers memory p1 = _getPowers(token, user1);
            assertEq(p1.localPower, 150e18, "2: local power of user 1");
            assertEq(p1.otherPower, 1000e18, "2: other power of user 1 (delegated to user 2)");
            assertEq(p1.delegatedLocalPower, 0, "2: delegated local power of user 1");
            assertEq(p1.delegatedOtherPower, 0, "2: delegated other power of user 1");

            Powers memory p2 = _getPowers(token, user2);
            assertEq(p2.localPower, 250e18, "2: local power of user 2");
            assertEq(p2.otherPower, 2000e18, "2: other power of user 2");
            assertEq(p2.delegatedLocalPower, 150e18, "2: delegated local power of user 2");
            assertEq(p2.delegatedOtherPower, 1000e18, "2: delegated other power of user 2");
        }

        // -------------------------- set power on other chains for user 1 and user 3, user 3 delegates to user 2
        {
            vm.prank(user3);
            token.setPowerDelegation(user2);

            // assume here that user2 has lost his power on other chains
            // so, user 2 is not included to updateOtherChainsPowers

            address[] memory users = new address[](2);
            users[0] = user1;
            users[1] = user3;
            uint[] memory powers = new uint[](2);
            powers[0] = 1000e18;
            powers[1] = 3000e18;

            vm.prank(user1);
            token.updateOtherChainsPowers(users, powers);
            skip(1); // in next tx we should have different timestamp because it's used as an epoch counter inside token
        }

        // -------------------------- check updated vote powers
        {
            assertEq(token.getVotes(user1), 0, "3: getVotes user 1");
            assertEq(token.getVotes(user2), 3000e18 + 250e18 + 150e18 + 1000e18, "3: getVotes user 2");
            assertEq(token.getVotes(user3), 0, "3: getVotes user 3");

            Powers memory p1 = _getPowers(token, user1);
            assertEq(p1.localPower, 150e18, "3: local power of user 1");
            assertEq(p1.otherPower, 1000e18, "3: other power of user 1 (delegated to user 2)");
            assertEq(p1.delegatedLocalPower, 0, "3: delegated local power of user 1");
            assertEq(p1.delegatedOtherPower, 0, "3: delegated other power of user 1");

            Powers memory p2 = _getPowers(token, user2);
            assertEq(p2.localPower, 250e18, "3: local power of user 2");
            assertEq(p2.otherPower, 0, "3: other power of user 2");
            assertEq(p2.delegatedLocalPower, 150e18, "3: delegated local power of user 2 (from user 1)");
            assertEq(p2.delegatedOtherPower, 1000e18 + 3000e18, "3: delegated other power of user 2 (from 1 and 3)");

            Powers memory p3 = _getPowers(token, user3);
            assertEq(p3.localPower, 0, "3: local power of user 3");
            assertEq(p3.otherPower, 3000e18, "3: other power of user 3 (delegated to user 2)");
            assertEq(p3.delegatedLocalPower, 0, "3: delegated local power of user 3");
            assertEq(p3.delegatedOtherPower, 0, "3: delegated other power of user 3");
        }
    }

    function testDistributeBribes() public {
        // Assume following situation:
        // Sonic: U1: 100, U2: 200, U3: 300, U4: 400
        // Delegation on Sonic: U1 => U2, U3 => U2
        // Plasma: U1: 50, U2: 150, U4: 250
        // Avalanche: U1: 600, U3: 500
        //
        // Suppose, U2 votes and receives 1000 bribes
        // How to distribute the bribes between the users?
        //
        // Total number of votes of U2: (U1.sonic + U1.plasma + U1.avalanche) + (U2.sonic + U2.plasma) + (U3.sonic + U3.avalanche)
        // (100 + 50 + 600) + (200 + 150) + (300 + 500) = 1900
        // U1: 1000 bribes * 750 / 1900
        // U2: 1000 bribes * 350 / 1900
        // U3: 1000 bribes * 800 / 1900

        IStabilityDAO token = _createDAOInstance();

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        address user4 = makeAddr("user4");

        // -------------------------- provide powers for user 1 and user 2 on main chain
        deal(address(token), user1, 100e18);
        deal(address(token), user2, 200e18);
        deal(address(token), user3, 300e18);
        deal(address(token), user4, 400e18);

        // -------------------------- set power on other chains for user 1 and user 2
        {
            address[] memory users = new address[](4);
            users[0] = user1;
            users[1] = user2;
            users[2] = user3;
            users[3] = user4;
            uint[] memory powers = new uint[](4);
            powers[0] = 50e18 + 600e18;
            powers[1] = 150e18;
            powers[2] = 500e18;
            powers[3] = 250e18;

            vm.prank(multisig);
            token.setWhitelistedForOtherChainsPowers(user1, true);

            vm.prank(user1);
            token.updateOtherChainsPowers(users, powers);
            skip(1); // in next tx we should have different timestamp because it's used as an epoch counter inside token
        }

        // -------------------------- users 1 and 3 delegate their powers to user 2
        vm.prank(user1);
        token.setPowerDelegation(user2);

        vm.prank(user3);
        token.setPowerDelegation(user2);

        // -------------------------- distribute bribes
        Powers memory p1 = _getPowers(token, user1);
        Powers memory p2 = _getPowers(token, user2);
        Powers memory p3 = _getPowers(token, user3);
        (, address[] memory delegators) = token.delegates(user2);

        //        _showPowers(p1);
        //        _showPowers(p2);
        //        _showPowers(p3);

        assertEq(delegators.length, 2, "delegators are users 1 and 3");
        assertEq(delegators[0], user1, "first delegator is user 1");
        assertEq(delegators[1], user3, "second delegator is user 3");

        assertEq(
            p2.localPower + p2.otherPower + p2.delegatedLocalPower + p2.delegatedOtherPower,
            1900e18,
            "total power of user 2"
        );
        assertEq(p1.localPower + p1.otherPower, 750e18, "total power of user 1");
        assertEq(p2.localPower + p2.otherPower, 350e18, "total power of user 2");
        assertEq(p3.localPower + p3.otherPower, 800e18, "total power of user 3");

        assertEq(p2.delegatedLocalPower + p2.delegatedOtherPower, 1900e18 - 350e18, "delegated power of user 2");
    }

    //endregion --------------------------------- Unit tests

    //region --------------------------------- Utils
    function _getPowers(IStabilityDAO dao, address user) internal view returns (Powers memory p) {
        (p.localPower, p.otherPower, p.delegatedLocalPower, p.delegatedOtherPower) = dao.getPowers(user);
        return p;
    }

    function _showPowers(Powers memory p) internal pure {
        console.log("localPower", p.localPower);
        console.log("otherPower", p.otherPower);
        console.log("delegatedLocalPower", p.delegatedLocalPower);
        console.log("delegatedOtherPower", p.delegatedOtherPower);
    }

    function _updateConfig(
        IStabilityDAO token,
        address user,
        IStabilityDAO.DaoParams memory p2
    ) internal returns (IStabilityDAO.DaoParams memory dest) {
        uint snapshot = vm.snapshotState();
        vm.prank(user);
        token.updateConfig(p2);
        dest = token.config();

        vm.revertToState(snapshot);
        return dest;
    }

    function _createDAOInstance() internal returns (IStabilityDAO) {
        IStabilityDAO.DaoParams memory p = IStabilityDAO.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 80_00,
            quorum: 15_000,
            proposalThreshold: 25_000,
            powerAllocationDelay: 86400
        });
        return _createDAOInstance(p);
    }

    function _createDAOInstance(IStabilityDAO.DaoParams memory p) internal returns (IStabilityDAO) {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new DAO()));
        IStabilityDAO token = IStabilityDAO(address(proxy));
        token.initialize(
            SonicConstantsLib.PLATFORM,
            SonicConstantsLib.TOKEN_STBL,
            SonicConstantsLib.XSTBL_XSTAKING,
            p,
            "Stability DAO",
            "STBL_DAO"
        );
        return token;
    }

    function _upgradePlatform() internal {
        rewind(1 days);

        IPlatform platform = IPlatform(SonicConstantsLib.PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = SonicConstantsLib.PLATFORM;

        implementations[0] = address(new Platform());

        vm.startPrank(platform.multisig());
        platform.announcePlatformUpgrade("2025.08.21-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }
    //endregion --------------------------------- Utils
}
