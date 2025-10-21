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
import {Platform} from "../../src/core/Platform.sol";

contract StabilityDAOSonicTest is Test {
    using SafeERC20 for IERC20;

    uint public constant FORK_BLOCK = 47854805; // Sep-23-2025 04:02:39 AM +UTC
    address internal multisig;

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

        IStabilityDAO token = _createStabilityDAOInstance(p1);

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
            proposalThreshold: 10_00, // 10%
            quorum: 20_00, // 20%
            powerAllocationDelay: 86400
        });
        IStabilityDAO token = _createStabilityDAOInstance(p1);

        p1.proposalThreshold = 100_00; // 100%

        vm.prank(multisig);
        vm.expectRevert(StabilityDAO.WrongValue.selector);
        token.updateConfig(p1);

        p1.proposalThreshold = 10_00;
        p1.exitPenalty = 100_00; // 100%

        vm.prank(multisig);
        vm.expectRevert(StabilityDAO.WrongValue.selector);
        token.updateConfig(p1);

        p1.exitPenalty = 50_00;
        p1.quorum = 100_00; // 100%

        vm.prank(multisig);
        vm.expectRevert(StabilityDAO.WrongValue.selector);
        token.updateConfig(p1);
    }

    function testNonTransferable() public {
        IStabilityDAO token = _createStabilityDAOInstance();

        vm.prank(token.xStaking());
        token.mint(address(0x123), 1e18);

        vm.prank(address(0x123));
        vm.expectRevert(StabilityDAO.NonTransferable.selector);
        //slither-disable-next-line erc20-unchecked-transfer
        token.transfer(address(0x456), 1e18);

        vm.prank(address(0x123));
        token.approve(address(0x456), 1e18);

        vm.prank(address(0x456));
        vm.expectRevert(StabilityDAO.NonTransferable.selector);
        //slither-disable-next-line erc20-unchecked-transfer
        token.transferFrom(address(0x123), address(0x789), 1e18);
    }

    function testSetPowerDelegation() public {
        address user1 = address(1);
        address user2 = address(2);
        IStabilityDAO stabilityDao = _createStabilityDAOInstance();

        // ---------------------------- Initial state
        vm.prank(stabilityDao.xStaking());
        stabilityDao.mint(user1, 10_000e18);

        vm.prank(stabilityDao.xStaking());
        stabilityDao.mint(user2, 20_000e18);

        assertEq(stabilityDao.userPower(user1), 10_000e18);
        assertEq(stabilityDao.userPower(user2), 20_000e18);

        (address delegatedTo, address[] memory delegates) = stabilityDao.delegates(user1);
        assertEq(delegatedTo, address(0));
        assertEq(delegates.length, 0);

        // ---------------------------- User 1 delegates to User 2
        vm.prank(user1);
        stabilityDao.setPowerDelegation(user2);

        vm.expectRevert(StabilityDAO.AlreadyDelegated.selector);
        vm.prank(user1);
        stabilityDao.setPowerDelegation(address(this));

        assertEq(stabilityDao.userPower(user1), 0);
        assertEq(stabilityDao.userPower(user2), 20_000e18 + 10_000e18);

        (delegatedTo, delegates) = stabilityDao.delegates(user1);
        assertEq(delegatedTo, user2);
        assertEq(delegates.length, 0);

        (delegatedTo, delegates) = stabilityDao.delegates(user2);
        assertEq(delegatedTo, address(0));
        assertEq(delegates.length, 1);
        assertEq(delegates[0], user1);

        // ---------------------------- User 2 delegates to User 1
        vm.prank(user2);
        stabilityDao.setPowerDelegation(user1);

        assertEq(stabilityDao.userPower(user1), 20_000e18);
        assertEq(stabilityDao.userPower(user2), 10_000e18);

        (delegatedTo, delegates) = stabilityDao.delegates(user1);
        assertEq(delegatedTo, user2);
        assertEq(delegates.length, 1);
        assertEq(delegates[0], user2);

        (delegatedTo, delegates) = stabilityDao.delegates(user2);
        assertEq(delegatedTo, user1);
        assertEq(delegates.length, 1);
        assertEq(delegates[0], user1);

        // ---------------------------- Both Users clear delegations
        vm.prank(user1);
        stabilityDao.setPowerDelegation(user1);

        vm.prank(user2);
        stabilityDao.setPowerDelegation(address(0));

        assertEq(stabilityDao.userPower(user1), 10_000e18);
        assertEq(stabilityDao.userPower(user2), 20_000e18);

        (delegatedTo, delegates) = stabilityDao.delegates(user1);
        assertEq(delegatedTo, address(0));
        assertEq(delegates.length, 0);

        (delegatedTo, delegates) = stabilityDao.delegates(user2);
        assertEq(delegatedTo, address(0));
        assertEq(delegates.length, 0);
    }

    //endregion --------------------------------- Unit tests

    //region --------------------------------- Utils
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

    function _createStabilityDAOInstance() internal returns (IStabilityDAO) {
        IStabilityDAO.DaoParams memory p = IStabilityDAO.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 80_00,
            quorum: 15_00,
            proposalThreshold: 25_00,
            powerAllocationDelay: 86400
        });
        return _createStabilityDAOInstance(p);
    }

    function _createStabilityDAOInstance(IStabilityDAO.DaoParams memory p) internal returns (IStabilityDAO) {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new StabilityDAO()));
        IStabilityDAO token = IStabilityDAO(address(proxy));
        token.initialize(SonicConstantsLib.PLATFORM, SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.XSTBL_XSTAKING, p);
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
