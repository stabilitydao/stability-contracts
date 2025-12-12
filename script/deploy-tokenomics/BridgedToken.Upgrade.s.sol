// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {StdConfig} from "forge-std/StdConfig.sol";
import {Variable, LibVariable} from "forge-std/LibVariable.sol";
import {Script} from "forge-std/Script.sol";
import {BridgedToken} from "../../src/tokenomics/BridgedToken.sol";

contract DeployBridgedTokenImplementation is Script {
    using LibVariable for Variable;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        StdConfig config = new StdConfig("./config.toml", false); // read only config

        vm.startBroadcast(deployerPrivateKey);
        new BridgedToken(config.get("LAYER_ZERO_V2_ENDPOINT").toAddress());

        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
