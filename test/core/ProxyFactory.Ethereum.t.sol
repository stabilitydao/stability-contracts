// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EthereumSetup} from "../base/chains/EthereumSetup.sol";
import {ProxyFactory, IProxyFactory, Proxy} from "../../src/core/ProxyFactory.sol";
import {Swapper} from "../../src/core/Swapper.sol";

contract ProxyFactoryEthereumTest is EthereumSetup {
    IProxyFactory public proxyFactory;

    constructor() {
        vm.rollFork(23600000); // Oct-17-2025 09:15:23 PM +UTC
        _init();
    }

    function setUp() public {
        ProxyFactory implementation = new ProxyFactory();
        Proxy proxy = new Proxy();
        proxy.initProxy(address(implementation));
        proxyFactory = IProxyFactory(address(proxy));
        proxyFactory.initialize(address(platform));
    }

    function testProxyFactory() public {
        //console.logBytes32(proxyFactory.getProxyInitCodeHash());
        //console.log(address (proxyFactory));
        //assertEq(proxyFactory.getProxyInitCodeHash(), 0x83e57d2d2b2765120795e70721641dfd7fbfb8130cf002195d9fbfeb619fb88a);
        proxyFactory.getProxyInitCodeHash();
        address deployedProxy = proxyFactory.deployProxy("0x00", address(new Swapper()));
        assertEq(deployedProxy, proxyFactory.getCreate2Address("0x00"));
    }
}
