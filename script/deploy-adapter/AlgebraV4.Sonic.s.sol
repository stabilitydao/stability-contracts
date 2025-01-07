// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/core/proxy/Proxy.sol";
import "../../src/adapters/AlgebraV4Adapter.sol";

contract DeployAlgebraV4AdapterSonic is Script {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new AlgebraV4Adapter()));
        AlgebraV4Adapter(address(proxy)).init(PLATFORM);

        vm.stopBroadcast();
    }

    function testDeployAdapter() external {}
}
