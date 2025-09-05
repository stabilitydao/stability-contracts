// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {TokenSender} from "../../src/tokenomics/TokenSender.sol";

contract DeployTokenSender is Script {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new TokenSender(PLATFORM);
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
