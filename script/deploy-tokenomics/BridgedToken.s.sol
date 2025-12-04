// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {StdConfig} from "forge-std/StdConfig.sol";
import {Variable, LibVariable} from "forge-std/LibVariable.sol";
import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {BridgedToken} from "../../src/tokenomics/BridgedToken.sol";

contract DeployBridgedToken is Script {
    using LibVariable for Variable;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // ---------------------- Initialize
        StdConfig config = new StdConfig("./config.toml", false); // read only config
        StdConfig configDeployed = new StdConfig("./config.d.toml", true); // auto-write deployed addresses

        require(configDeployed.get("OAPP_STBL").toAddress() == address(0), "OAPP_STBL already deployed");

        // ---------------------- Deploy
        vm.startBroadcast(deployerPrivateKey);
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BridgedToken(config.get("LAYER_ZERO_V2_ENDPOINT").toAddress())));
        BridgedToken(address(proxy)).initialize(config.get("PLATFORM").toAddress(), "Stability STBL", "STBL");

        // ---------------------- Write results
        vm.stopBroadcast();

        configDeployed.set("OAPP_STBL", address(proxy));
    }

    function testDeployScript() external {}
}
