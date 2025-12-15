// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SolidlyAdapter} from "../../src/adapters/SolidlyAdapter.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";

contract DeploySolidlyAdapterSonic is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new SolidlyAdapter()));
        SolidlyAdapter(address(proxy)).init(PlasmaConstantsLib.PLATFORM);
        vm.stopBroadcast();
    }

    function testDeployAdapter() external {}
}
