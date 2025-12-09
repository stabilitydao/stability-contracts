// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StdConfig} from "forge-std/StdConfig.sol";
import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {RecoveryRelayer} from "../../src/tokenomics/RecoveryRelayer.sol";
import {console} from "forge-std/console.sol";

contract DeployRecoveryRelayer is Script {
    uint internal constant SONIC_CHAIN_ID = 146;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // ---------------------- Initialize
        StdConfig config = new StdConfig("./config.toml", false); // read only config
        StdConfig configDeployed = new StdConfig("./config.d.toml", true); // auto-write deployed addresses

        require(
            block.chainid != SONIC_CHAIN_ID,
            "Recovery is used on Sonic instead of RecoveryRelayer, deploy is not allowed"
        );

        // todo how to implement such check?
        //        require(
        //            uint(configDeployed.get("recoveryRelayer").ty.kind) == 0, "recoveryRelayer is already deployed on the chain"
        //        );

        require(uint(config.get("PLATFORM").ty.kind) != 0, "Platform is not deployed on the chain");
        address platform = config.get("PLATFORM").toAddress();

        // ---------------------- Deploy
        vm.startBroadcast(deployerPrivateKey);

        Proxy proxy = new Proxy();
        {
            address implementation = address(new RecoveryRelayer());
            proxy.initProxy(implementation);
            require(proxy.implementation() == implementation, "RecoveryRelayer: implementation mismatch");
        }

        RecoveryRelayer(address(proxy)).initialize(platform);

        // ---------------------- Write results
        vm.stopBroadcast();

        configDeployed.set("recoveryRelayer", address(proxy));
    }

    function testDeployScript() external {}
}
