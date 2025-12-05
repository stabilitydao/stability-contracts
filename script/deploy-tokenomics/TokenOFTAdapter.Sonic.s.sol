// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {StdConfig} from "forge-std/StdConfig.sol";
import {Variable, LibVariable} from "forge-std/LibVariable.sol";
import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {TokenOFTAdapter} from "../../src/tokenomics/TokenOFTAdapter.sol";

contract DeployTokenOFTAdapterSonic is Script {
    using LibVariable for Variable;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address delegator = vm.envAddress("LZ_DELEGATOR");
        require(delegator != address(0), "delegator is not set");

        // ---------------------- Initialize
        StdConfig config = new StdConfig("./config.toml", false); // read only config
        StdConfig configDeployed = new StdConfig("./config.d.toml", true); // auto-write deployed addresses

        require(configDeployed.get("OAPP_MAIN_TOKEN").toAddress() == address(0), "OAPP_MAIN_TOKEN already deployed");
        require(
            block.chainid == 146, "TokenOFTAdapter is used on the Sonic only (the chain where native STBL is deployed)"
        );

        // ---------------------- Deploy
        vm.startBroadcast(deployerPrivateKey);
        Proxy proxy = new Proxy();
        proxy.initProxy(
            address(
                new TokenOFTAdapter(
                    config.get("TOKEN_STBL").toAddress(), config.get("LAYER_ZERO_V2_ENDPOINT").toAddress()
                )
            )
        );
        TokenOFTAdapter(address(proxy)).initialize(config.get("PLATFORM").toAddress(), delegator);

        // ---------------------- Write results
        vm.stopBroadcast();

        configDeployed.set("OAPP_MAIN_TOKEN", address(proxy));
    }

    function testDeployScript() external {}
}
