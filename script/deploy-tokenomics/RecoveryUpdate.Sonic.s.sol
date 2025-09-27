// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Recovery} from "../../src/tokenomics/Recovery.sol";

contract DeployRecoverySonicUpdate is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new Recovery();
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
