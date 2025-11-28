// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {StdConfig} from "forge-std/StdConfig.sol";
import {Variable, LibVariable} from "forge-std/LibVariable.sol";
import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {BridgedPriceOracle} from "../../src/periphery/BridgedPriceOracle.sol";

contract DeployBridgedToken is Script {
    using LibVariable for Variable;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        StdConfig config = new StdConfig("./config.toml", false); // read only config
        StdConfig configDeployed = new StdConfig("./config.d.toml", true); // auto-write deployed addresses

        vm.startBroadcast(deployerPrivateKey);
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BridgedPriceOracle(config.get("LAYER_ZERO_V2_ENDPOINT").toAddress())));

        // @dev assume here that we deploy price oracle for STBL token
        BridgedPriceOracle(address(proxy)).initialize(config.get("PLATFORM").toAddress(), "STBL");

        vm.stopBroadcast();

        // @dev assume here that we deploy price oracle for STBL token
        configDeployed.set("BRIDGED_PRICE_ORACLE_STBL", address(proxy));
    }

    function testDeployScript() external {}
}
