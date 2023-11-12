// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import "../../src/core/vaults/CVault.sol";
import "../../src/core/proxy/Proxy.sol";
import "../../src/test/MockVaultUpgrade.sol";
import "../base/MockSetup.sol";

contract ProxyTest is Test, MockSetup {
    Proxy public proxy;
    MockVaultUpgrade public vaultImplementationUpgrade;

    function setUp() public {
        proxy = new Proxy();
        vaultImplementationUpgrade = new MockVaultUpgrade();
    }

    function testInitProxy() public {
        proxy.initProxy(address(vaultImplementation));
        vm.expectRevert(bytes("Already inited"));
        proxy.initProxy(address(vaultImplementation));
    }

    function testUpgrade() public {
        proxy.initProxy(address(vaultImplementation));
        CVault vault = CVault(payable(address(proxy)));
        vault.initialize(address(platform), address(0), 'V', 'V', 0, new address[](0), new uint[](0));

        // IControllable
        assertEq(proxy.implementation(), address(vaultImplementation));
        assertGt(vault.createdBlock(), 0);
        assertEq(IControllable(address(vault)).platform(), address(platform));

        vm.expectRevert("Proxy: Forbidden");
        proxy.upgrade(address(vaultImplementationUpgrade));

        vm.prank(address(platform));
        proxy.upgrade(address(vaultImplementationUpgrade));

        assertEq(vault.VERSION(), '10.99.99');

        // IControllable
        assertEq(proxy.implementation(), address(vaultImplementationUpgrade));
        assertGt(vault.createdBlock(), 0);
        assertEq(IControllable(address(vault)).platform(), address(platform));
    }
}