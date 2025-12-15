// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StdConfig} from "forge-std/StdConfig.sol";
import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {XTokenBridge} from "../../src/tokenomics/XTokenBridge.sol";

contract DeployXTokenBridge is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // ---------------------- Initialize
        StdConfig config = new StdConfig("./config.toml", false); // read only config
        StdConfig configDeployed = new StdConfig("./config.d.toml", true); // auto-write deployed addresses

        require(
            uint(configDeployed.get("OAPP_MAIN_TOKEN").ty.kind) != 0, "OAPP_MAIN_TOKEN is not deployed on the chain"
        );
        address bridge = configDeployed.get("OAPP_MAIN_TOKEN").toAddress();

        require(uint(configDeployed.get("xToken").ty.kind) != 0, "xToken is not deployed on the chain");
        address xToken = configDeployed.get("xToken").toAddress();

        require(uint(config.get("PLATFORM").ty.kind) != 0, "platform is not set");
        address platform = config.get("PLATFORM").toAddress();

        require(uint(config.get("LAYER_ZERO_V2_ENDPOINT").ty.kind) != 0, "endpoint is not set");
        address endpoint = config.get("LAYER_ZERO_V2_ENDPOINT").toAddress();

        require(uint(configDeployed.get("XTokenBridge").ty.kind) == 0, "XTokenBridge already deployed");

        // ---------------------- Deploy
        vm.startBroadcast(deployerPrivateKey);

        Proxy proxy = new Proxy();
        {
            address implementation = address(new XTokenBridge(endpoint));
            proxy.initProxy(implementation);
            require(proxy.implementation() == implementation, "XTokenBridge: implementation mismatch");
        }

        XTokenBridge(address(proxy)).initialize(platform, bridge, address(xToken));

        // ---------------------- Write results
        vm.stopBroadcast();

        configDeployed.set("XTokenBridge", address(proxy));
    }

    function testDeployScript() external {}
}
