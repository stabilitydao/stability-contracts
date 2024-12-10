// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/core/proxy/Proxy.sol";
import "../../src/adapters/SolidlyAdapter.sol";

contract DeploySolidlyAdapterReal is Script {
    address public constant PLATFORM = 0xB7838d447deece2a9A5794De0f342B47d0c1B9DC;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new SolidlyAdapter()));
        SolidlyAdapter(address(proxy)).init(PLATFORM);

        vm.stopBroadcast();
    }

    function testDeployAdapter() external {}
}
