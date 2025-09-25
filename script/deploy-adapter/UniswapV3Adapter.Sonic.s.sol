// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {UniswapV3Adapter} from "../../src/adapters/UniswapV3Adapter.sol";

contract DeployUniswapV3AdapterSonic is Script {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        //proxy was already deployed, we need to update implementation only
        new UniswapV3Adapter();

        vm.stopBroadcast();
    }

    function testDeployAdapter() external {}
}
