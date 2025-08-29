// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {MockVaultUpgrade} from "../../src/test/MockVaultUpgrade.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {MockStrategy} from "../../src/test/MockStrategy.sol";
import {BadUpgrade} from "../../src/test/BadUpgrade.sol";
import {MockSetup} from "../base/MockSetup.sol";

contract ProxyTest is Test, MockSetup {
    Proxy public proxy;
    MockVaultUpgrade public vaultImplementationUpgrade;
    BadUpgrade public badUpgrade;
    MockStrategy public strategyImplementation;
    MockStrategy public strategy;

    function setUp() public {
        proxy = new Proxy();
        vaultImplementationUpgrade = new MockVaultUpgrade();
        badUpgrade = new BadUpgrade();
        strategyImplementation = new MockStrategy();
        Proxy strategyProxy = new Proxy();
        strategyProxy.initProxy(address(strategyImplementation));
        strategy = MockStrategy(address(strategyProxy));
    }

    function testInitProxy() public {
        proxy.initProxy(address(vaultImplementation));
        vm.expectRevert(bytes("Already inited"));
        proxy.initProxy(address(vaultImplementation));
    }

    function testUpgrade() public {
        proxy.initProxy(address(vaultImplementation));
        CVault vault = CVault(payable(address(proxy)));

        vault.initialize(
            IVault.VaultInitializationData({
                platform: address(platform),
                strategy: address(strategy),
                name: "V",
                symbol: "V",
                tokenId: 0,
                vaultInitAddresses: new address[](0),
                vaultInitNums: new uint[](0)
            })
        );

        // IControllable
        assertEq(proxy.implementation(), address(vaultImplementation));
        assertGt(vault.createdBlock(), 0);
        assertEq(IControllable(address(vault)).platform(), address(platform));

        vm.expectRevert(IControllable.NotPlatform.selector);
        proxy.upgrade(address(vaultImplementationUpgrade));

        vm.prank(address(platform));
        proxy.upgrade(address(vaultImplementationUpgrade));

        assertEq(vault.VERSION(), "10.99.99");

        // IControllable
        assertEq(proxy.implementation(), address(vaultImplementationUpgrade));
        assertGt(vault.createdBlock(), 0);
        assertEq(IControllable(address(vault)).platform(), address(platform));

        vm.prank(address(platform));
        vm.expectRevert(IControllable.NotPlatform.selector);
        proxy.upgrade(address(badUpgrade));
    }
}
