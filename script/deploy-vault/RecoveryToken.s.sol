// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {RecoveryToken} from "../../src/core/vaults/RecoveryToken.sol";

contract DeployRecoveryToken is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new RecoveryToken();
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
