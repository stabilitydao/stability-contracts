// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {MerkleDistributor} from "../../src/tokenomics/MerkleDistributor.sol";

contract DeployMerkleDistributor is Script {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new MerkleDistributor()));
        MerkleDistributor(address(proxy)).initialize(PLATFORM);
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}