// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {BalancerV3ReClammAdapter} from "../../src/adapters/BalancerV3ReClammAdapter.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";

contract DeployBalancerV3StableAdapterPlasma is Script {
    // address public constant PLATFORM = todo;

    function run() external {
// todo
//        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//        vm.startBroadcast(deployerPrivateKey);
//        Proxy proxy = new Proxy();
//        proxy.initProxy(address(new BalancerV3ReClammAdapter()));
//        BalancerV3ReClammAdapter(address(proxy)).init(PLATFORM);
//        vm.stopBroadcast();
    }

    function testDeployAdapter() external {}
}
