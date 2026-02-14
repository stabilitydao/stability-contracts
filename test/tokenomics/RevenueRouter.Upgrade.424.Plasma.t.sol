// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";
import {IControllable} from "../../src/core/Platform.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {RevenueRouter, IRevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";
import {Test} from "forge-std/Test.sol";

contract RevenueRouterUpgrade424TestPlasma is Test {
    uint public constant FORK_BLOCK = 8339817; // Dec-9-2025 08:54:48 UTC
    address public constant PLATFORM = PlasmaConstantsLib.PLATFORM;
    address public multisig;
    IRevenueRouter public revenueRouter;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("PLASMA_RPC_URL"), FORK_BLOCK));
        revenueRouter = IRevenueRouter(IPlatform(PLATFORM).revenueRouter());
        multisig = IPlatform(PLATFORM).multisig();

        _upgradeRevenueRouter();
    }

    function testSetAddresses() public {
        // Addresses of main-token, xToken, xStaking and feeTreasure token
        address[] memory addr = revenueRouter.addresses();
        addr[0] = address(0x1);
        addr[1] = address(0x2);
        addr[2] = address(0x3);
        addr[3] = address(0x4);

        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        vm.prank(makeAddr("not multisig"));
        revenueRouter.setAddresses(addr);

        vm.prank(multisig);
        revenueRouter.setAddresses(addr);

        address[] memory addrAfter = revenueRouter.addresses();
        assertEq(addr[0], addrAfter[0], "main-token address mismatch");
        assertEq(addr[1], addrAfter[1], "xToken address mismatch");
        assertEq(addr[2], addrAfter[2], "xStaking address mismatch");
        assertEq(addr[3], addrAfter[3], "feeTreasure address mismatch");
    }

    function _upgradeRevenueRouter() internal {
        address[] memory proxies = new address[](1);
        proxies[0] = address(revenueRouter);
        address[] memory implementations = new address[](1);
        implementations[0] = address(new RevenueRouter());
        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.12.0-alpha", proxies, implementations);
        skip(18 hours);
        IPlatform(PLATFORM).upgrade();
        vm.stopPrank();
        rewind(17 hours);
    }
}
