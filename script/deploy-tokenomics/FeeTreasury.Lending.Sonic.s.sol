// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {FeeTreasury} from "../../src/tokenomics/FeeTreasury.sol";

contract DeployFeeTreasuryLendingSonic is Script {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant MANAGER = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new FeeTreasury()));
        FeeTreasury(address(proxy)).initialize(PLATFORM);
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
