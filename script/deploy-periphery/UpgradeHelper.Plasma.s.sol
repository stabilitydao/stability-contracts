// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";
import {Script} from "forge-std/Script.sol";
import {UpgradeHelper} from "../../src/periphery/UpgradeHelper.sol";

contract DeployUpgradeHelperPlasma is Script {
    address public constant PLATFORM = 0xd4D6ad656f64E8644AFa18e7CCc9372E0Cd256f0;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new UpgradeHelper(PLATFORM);
        vm.stopBroadcast();
    }

    function testDeployPeriphery() external {}
}
