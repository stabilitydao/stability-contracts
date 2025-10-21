// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {LiquidationBot} from "../../src/periphery/LiquidationBot.sol";

contract DeployLiquidationBot is Script {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new LiquidationBot()));
        LiquidationBot(address(proxy)).initialize(PLATFORM);
        vm.stopBroadcast();
    }

    function testDeployAdapter() external {}
}
