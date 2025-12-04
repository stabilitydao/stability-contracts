// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {StdConfig} from "forge-std/StdConfig.sol";
import {Variable, LibVariable} from "forge-std/LibVariable.sol";
import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {PriceAggregatorOApp} from "../../src/periphery/PriceAggregatorOApp.sol";

contract DeployPriceAggregatorOAppSonic is Script {
    using LibVariable for Variable;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // ---------------------- Initialize
        StdConfig config = new StdConfig("./config.toml", false); // read only config
        StdConfig configDeployed = new StdConfig("./config.d.toml", true); // auto-write deployed addresses

        require(block.chainid == 146, "PriceAggregatorOApp is used on the Sonic only (the chain where native STBL is deployed)");
        require(configDeployed.get("PRICE_AGGREGATOR_OAPP_STBL").toAddress() == address(0), "PriceAggregatorOApp already deployed");

        // ---------------------- Deploy
        vm.startBroadcast(deployerPrivateKey);
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new PriceAggregatorOApp(config.get("LAYER_ZERO_V2_ENDPOINT").toAddress())));

        // @dev assume here that we deploy price oracle for STBL token
        PriceAggregatorOApp(address(proxy))
            .initialize(config.get("PLATFORM").toAddress(), config.get("TOKEN_STBL").toAddress());

        // ---------------------- Write results
        vm.stopBroadcast();

        // @dev assume here that we deploy price oracle for STBL token
        configDeployed.set("PRICE_AGGREGATOR_OAPP_STBL", address(proxy));
    }

    function testDeployScript() external {}
}
