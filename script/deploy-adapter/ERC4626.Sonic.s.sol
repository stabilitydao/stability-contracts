// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {ERC4626Adapter} from "../../src/adapters/ERC4626Adapter.sol";

contract DeployERC4626AdapterSonic is Script {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new ERC4626Adapter()));
        ERC4626Adapter(address(proxy)).init(PLATFORM);
        vm.stopBroadcast();
    }

    function testDeployAdapter() external {}
}
