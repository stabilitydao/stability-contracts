// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StdConfig} from "forge-std/StdConfig.sol";
import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {XToken} from "../../src/tokenomics/XToken.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";

contract DeployXTokenSystem is Script {
    uint internal constant SONIC_CHAIN_ID = 146;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // ---------------------- Initialize
        StdConfig config = new StdConfig("./config.toml", false); // read only config
        StdConfig configDeployed = new StdConfig("./config.d.toml", true); // auto-write deployed addresses

        // Native STBL is deployed on Sonic. All other chains use bridged versions of STBL
        if (block.chainid != SONIC_CHAIN_ID) {
            require(uint(configDeployed.get("OAPP_MAIN_TOKEN").ty.kind) != 0, "Main token is not deployed on the chain");
        }
        address mainToken = block.chainid == SONIC_CHAIN_ID
            ? config.get("TOKEN_STBL").toAddress()
            : configDeployed.get("OAPP_MAIN_TOKEN").toAddress();

        require(uint(config.get("PLATFORM").ty.kind) != 0, "Platform is not deployed on the chain");
        address platform = config.get("PLATFORM").toAddress();

        address revenueRouter = address(IPlatform(platform).revenueRouter());
        require(revenueRouter != address(0), "RevenueRouter address is zero");

        require(uint(configDeployed.get("xToken").ty.kind) == 0, "xToken is already deployed on the chain");
        require(uint(configDeployed.get("xStaking").ty.kind) == 0, "xStaking is already deployed on the chain");

        // ---------------------- Deploy
        vm.startBroadcast(deployerPrivateKey);

        Proxy xStakingProxy = new Proxy();
        {
            address implementation = address(new XStaking());
            xStakingProxy.initProxy(implementation);
            require(xStakingProxy.implementation() == implementation, "XStaking: implementation mismatch");
        }

        Proxy xSTBLProxy = new Proxy();
        {
            address implementation = address(new XToken());
            xSTBLProxy.initProxy(implementation);
            require(xSTBLProxy.implementation() == implementation, "XToken: implementation mismatch");
        }

        XStaking(address(xStakingProxy)).initialize(platform, address(xSTBLProxy));
        XToken(address(xSTBLProxy))
            .initialize(platform, mainToken, address(xStakingProxy), revenueRouter, "xStability", "xSTBL");

        // ---------------------- Write results
        vm.stopBroadcast();

        configDeployed.set("xToken", address(xSTBLProxy));
        configDeployed.set("xStaking", address(xStakingProxy));
    }

    function testDeployScript() external {}
}
