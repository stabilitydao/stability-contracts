// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";
import {MockSetup} from "../base/MockSetup.sol";
import {TokenSender} from "../../src/tokenomics/TokenSender.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";

contract TokenSenderTest is Test, MockSetup {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STBL = 0x78a76316F66224CBaCA6e70acB24D5ee5b2Bd2c7;
    address public multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(12648494); // Mar-09-2025 01:28:58 PM +UTC
        multisig = IPlatform(PLATFORM).multisig();
    }

    function test_tokenSender() public {
        TokenSender tokenSender = new TokenSender(PLATFORM);
        vm.startPrank(multisig);
        IERC20(STBL).approve(address(tokenSender), 28_000e18);
        address[] memory receivers = new address[](3);
        receivers[0] = address(1);
        receivers[1] = address(2);
        receivers[2] = address(3);
        uint[] memory amounts = new uint[](3);
        amounts[0] = 1e18;
        amounts[1] = 11e18;
        amounts[2] = 111e18;
        tokenSender.send(STBL, receivers, amounts);
        vm.stopPrank();
        assertEq(IERC20(STBL).balanceOf(address(3)), 111e18);

        vm.expectRevert();
        tokenSender.send(STBL, receivers, amounts);
    }
}
