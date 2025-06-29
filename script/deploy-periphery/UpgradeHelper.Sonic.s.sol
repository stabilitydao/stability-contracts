// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {UpgradeHelper} from "../../src/periphery/UpgradeHelper.sol";

contract DeployFrontendSonic is Script {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new UpgradeHelper(PLATFORM);
        vm.stopBroadcast();
    }

    function testDeployPeriphery() external {}
}
