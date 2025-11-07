// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {StdConfig} from "forge-std/StdConfig.sol";
import {Variable, LibVariable} from "forge-std/LibVariable.sol";
import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {PriceAggregatorOApp} from "../../src/periphery/PriceAggregatorOApp.sol";

contract DeployPriceAggregatorOApp is Script {
    using LibVariable for Variable;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        StdConfig config = new StdConfig("./config.toml", false); // read only config
        StdConfig configDeployed = new StdConfig("./config.d.toml", true); // auto-write deployed addresses

        vm.startBroadcast(deployerPrivateKey);
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new PriceAggregatorOApp(config.get("LAYER_ZERO_V2_ENDPOINT").toAddress())));

        // @dev assume here that we deploy price oracle for STBL token
        PriceAggregatorOApp(address(proxy))
            .initialize(config.get("PLATFORM").toAddress(), config.get("TOKEN_STBL").toAddress());

        // @dev assume here that we deploy price oracle for STBL token
        configDeployed.set("PRICE_AGGREGATOR_OAPP_STBL", address(proxy));

        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
