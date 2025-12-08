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

        address bridge = configDeployed.get("OAPP_MAIN_TOKEN").toAddress();
        require(bridge != address(0), "OAPP is zero");

        address xToken = configDeployed.get("xToken").toAddress();
        require(xToken != address(0), "XSTBL address is zero");

        address platform = config.get("PLATFORM").toAddress();
        require(platform != address(0), "PLATFORM address is zero");

        address endpoint = config.get("LAYER_ZERO_V2_ENDPOINT").toAddress();
        require(endpoint != address(0), "endpoint is not set");

        require(configDeployed.get("XTokenBridge").toAddress() == address(0), "XTokenBridge already deployed");

        // ---------------------- Deploy
        vm.startBroadcast(deployerPrivateKey);

        Proxy proxy = new Proxy();
        {
            address implementation = address(new XTokenBridge(endpoint));
            proxy.initProxy(address(new XTokenBridge(endpoint)));
            require(proxy.implementation() == implementation, "XTokenBridge: implementation mismatch");
        }

        XTokenBridge(address(proxy)).initialize(platform, bridge, address(xToken));

        // ---------------------- Write results
        vm.stopBroadcast();

        configDeployed.set("XTokenBridge", address(proxy));
    }

    function testDeployScript() external {}
}
