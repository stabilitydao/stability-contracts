// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StdConfig} from "forge-std/StdConfig.sol";
import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {XToken} from "../../src/tokenomics/XToken.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";

contract DeployXTokenSystem is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // ---------------------- Initialize
        StdConfig config = new StdConfig("./config.toml", false); // read only config
        StdConfig configDeployed = new StdConfig("./config.d.toml", true); // auto-write deployed addresses

        // Native STBL is deployed on Sonic. All other chains use bridged versions of STBL
        address mainToken =
            block.chainid == 146 ? config.get("TOKEN_STBL").toAddress() : configDeployed.get("OAPP_STBL").toAddress();
        require(mainToken != address(0), "STBL address is zero");

        address platform = config.get("PLATFORM").toAddress();
        require(platform != address(0), "PLATFORM address is zero");

        address revenueRouter = address(IPlatform(platform).revenueRouter());
        require(revenueRouter != address(0), "RevenueRouter address is zero");

        require(config.get("xToken").toAddress() == address(0), "xToken is already deployed");
        require(config.get("xStaking").toAddress() == address(0), "xStaking is already deployed");

        // ---------------------- Deploy
        vm.startBroadcast(deployerPrivateKey);

        Proxy xStakingProxy = new Proxy();
        xStakingProxy.initProxy(address(new XStaking()));

        Proxy xSTBLProxy = new Proxy();
        xSTBLProxy.initProxy(address(new XToken()));

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
