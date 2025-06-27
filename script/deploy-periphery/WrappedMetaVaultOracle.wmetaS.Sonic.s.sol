// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Frontend} from "../../src/periphery/Frontend.sol";
import {WrappedMetaVaultOracle} from "../../src/periphery/WrappedMetaVaultOracle.sol";

contract DeployWrappedMetaVaultOraclewmetaSSonic is Script {
    address public constant WRAPPED_METAVAULT_metaS = 0xbbbbbbBBbd0aE69510cE374A86749f8276647B19;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new WrappedMetaVaultOracle(WRAPPED_METAVAULT_metaS);
        vm.stopBroadcast();
    }

    function testDeployPeriphery() external {}
}
