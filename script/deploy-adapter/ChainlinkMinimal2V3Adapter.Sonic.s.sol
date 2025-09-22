// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {ChainlinkMinimal2V3Adapter} from "../../src/adapters/ChainlinkMinimal2V3Adapter.sol";
import {Script} from "forge-std/Script.sol";

contract DeployChainlinkMinimal2V3AdapterSonic is Script {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // new ChainlinkMinimal2V3Adapter(SonicConstantsLib.ORACLE_CHAINLINK_METAUSD);
        new ChainlinkMinimal2V3Adapter(SonicConstantsLib.ORACLE_CHAINLINK_METAS);
        vm.stopBroadcast();
    }

    function testDeployAdapter() external {}
}
