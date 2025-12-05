// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {StdConfig} from "forge-std/StdConfig.sol";
import {Variable, LibVariable} from "forge-std/LibVariable.sol";
import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {BridgedPriceOracle} from "../../src/periphery/BridgedPriceOracle.sol";

contract DeployBridgedPriceOracle is Script {
    using LibVariable for Variable;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address delegator = vm.envAddress("LZ_DELEGATOR");
        require(delegator != address(0), "delegator is not set");

        // ---------------------- Initialize
        StdConfig config = new StdConfig("./config.toml", false); // read only config
        StdConfig configDeployed = new StdConfig("./config.d.toml", true); // auto-write deployed addresses

        require(
            configDeployed.get("BRIDGED_PRICE_ORACLE_MAIN_TOKEN").toAddress() == address(0),
            "BridgedPriceOracle already deployed"
        );

        // ---------------------- Deploy
        vm.startBroadcast(deployerPrivateKey);
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BridgedPriceOracle(config.get("LAYER_ZERO_V2_ENDPOINT").toAddress())));

        // @dev assume here that we deploy price oracle for STBL token
        BridgedPriceOracle(address(proxy)).initialize(config.get("PLATFORM").toAddress(), "STBL", delegator);

        // ---------------------- Write results
        vm.stopBroadcast();

        // @dev assume here that we deploy price oracle for STBL token
        configDeployed.set("BRIDGED_PRICE_ORACLE_MAIN_TOKEN", address(proxy));
    }

    function testDeployScript() external {}
}
