// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Recovery} from "../../src/tokenomics/Recovery.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";

contract DeployRecoverySonic is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new Recovery()));
        Recovery(address(proxy)).initialize(SonicConstantsLib.PLATFORM);
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
