// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IStabilityDaoToken} from "../../src/interfaces/IStabilityDaoToken.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Test} from "forge-std/Test.sol";
import {StabilityDaoToken} from "../../src/tokenomics/StabilityDaoToken.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StabilityDaoTokenSonicTest is Test {
    using SafeERC20 for IERC20;

    uint public constant FORK_BLOCK = 47854805; // Sep-23-2025 04:02:39 AM +UTC
    address internal multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();

        console.logBytes32(
            keccak256(abi.encode(uint(keccak256("erc7201:stability.StabilityDaoToken")) - 1)) & ~bytes32(uint(0xff))
        );
    }

    //region --------------------------------- Unit tests

    function testInitializeAndView() public {
        IStabilityDaoToken.DaoParams memory p = IStabilityDaoToken.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 5_000,
            proposalThreshold: 100_000,
            powerAllocationDelay: 86400
        });

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new StabilityDaoToken()));

        IStabilityDaoToken token = IStabilityDaoToken(address(proxy));
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
        IStabilityDaoToken token = createStabilityDaoTokenInstance();

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
        IStabilityDaoToken token = createStabilityDaoTokenInstance();

        IStabilityDaoToken.DaoParams memory p1 = IStabilityDaoToken.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 5_000,
            proposalThreshold: 100_000,
            powerAllocationDelay: 86400
        });

        IStabilityDaoToken.DaoParams memory p2 = IStabilityDaoToken.DaoParams({
            minimalPower: 5000e18,
            exitPenalty: 10_000,
            proposalThreshold: 200_000,
            powerAllocationDelay: 172800
        });

        IStabilityDaoToken.DaoParams memory config = token.config();
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

        vm.prank(multisig);
        token.updateConfig(p2);

        config = token.config();
        assertEq(config.minimalPower, p2.minimalPower);
        assertEq(config.exitPenalty, p2.exitPenalty);
        assertEq(config.proposalThreshold, p2.proposalThreshold);
        assertEq(config.powerAllocationDelay, p2.powerAllocationDelay);
    }

    function testNonTransferable() public {
        IStabilityDaoToken token = createStabilityDaoTokenInstance();

        vm.prank(token.xStaking());
        token.mint(address(0x123), 1e18);

        vm.prank(address(0x123));
        vm.expectRevert(StabilityDaoToken.NonTransferable.selector);
        token.transfer(address(0x456), 1e18);

        vm.prank(address(0x123));
        token.approve(address(0x456), 1e18);

        vm.prank(address(0x456));
        vm.expectRevert(StabilityDaoToken.NonTransferable.selector);
        token.transferFrom(address(0x123), address(0x789), 1e18);
    }

    //endregion --------------------------------- Unit tests

    //region --------------------------------- Test for uses cases

    // todo

    //endregion --------------------------------- Test for uses cases

    //region --------------------------------- Utils
    function createStabilityDaoTokenInstance() internal returns (IStabilityDaoToken) {
        IStabilityDaoToken.DaoParams memory p = IStabilityDaoToken.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 5_000,
            proposalThreshold: 100_000,
            powerAllocationDelay: 86400
        });

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new StabilityDaoToken()));
        IStabilityDaoToken token = IStabilityDaoToken(address(proxy));
        token.initialize(SonicConstantsLib.PLATFORM, SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.XSTBL_XSTAKING, p);
        return token;
    }
    //endregion --------------------------------- Utils
}
