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
        address delegator = vm.envAddress("LZ_DELEGATOR");
        require(delegator != address(0), "delegator is not set");

        // ---------------------- Initialize
        StdConfig config = new StdConfig("./config.toml", false); // read only config
        StdConfig configDeployed = new StdConfig("./config.d.toml", true); // auto-write deployed addresses

        require(
            uint(configDeployed.get("OAPP_MAIN_TOKEN").ty.kind) == 0,
            "TokenOFTAdapter is already deployed on this chain"
        );
        require(
            uint(config.get("LAYER_ZERO_V2_ENDPOINT").ty.kind) != 0,
            "endpoint is not set"
        );
        require(
            uint(config.get("PLATFORM").ty.kind) != 0,
            "platform is not set"
        );

        address endpoint = config.get("LAYER_ZERO_V2_ENDPOINT").toAddress();
        address platform = config.get("PLATFORM").toAddress();

        // ---------------------- Deploy
        vm.startBroadcast(deployerPrivateKey);
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BridgedToken(endpoint)));
        BridgedToken(address(proxy)).initialize(platform, "Stability STBL", "STBL", delegator);

        // ---------------------- Write results
        vm.stopBroadcast();

        configDeployed.set("OAPP_MAIN_TOKEN", address(proxy));
    }

    function testDeployScript() external {}
}
