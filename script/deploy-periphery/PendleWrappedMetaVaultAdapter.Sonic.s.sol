// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {PendleWrappedMetaVaultAdapter} from "../../src/periphery/PendleWrappedMetaVaultAdapter.sol";
import {Script} from "forge-std/Script.sol";

contract DeployPendleWrappedMetaVaultAdapterSonic is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // new PendleWrappedMetaVaultAdapter(SonicConstantsLib.METAVAULT_METAS);
        new PendleWrappedMetaVaultAdapter(SonicConstantsLib.METAVAULT_METAUSD);
        vm.stopBroadcast();
    }

    function testDeployAdapter() external {}
}
