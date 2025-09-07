// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {WrappedMetaVaultOracle} from "../../src/periphery/WrappedMetaVaultOracle.sol";

contract DeployWrappedMetaVaultOraclewmetaUSDSonic is Script {
    address public constant WRAPPED_METAVAULT_metaUSD = 0xAaAaaAAac311D0572Bffb4772fe985A750E88805;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new WrappedMetaVaultOracle(WRAPPED_METAVAULT_metaUSD);
        vm.stopBroadcast();
    }

    function testDeployPeriphery() external {}
}
