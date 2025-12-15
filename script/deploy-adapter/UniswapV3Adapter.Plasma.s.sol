// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {UniswapV3Adapter} from "../../src/adapters/UniswapV3Adapter.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";

contract DeployUniswapV3AdapterPlasma is Script {
    address public constant PLATFORM = PlasmaConstantsLib.PLATFORM;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new UniswapV3Adapter()));
        UniswapV3Adapter(address(proxy)).init(PLATFORM);

        vm.stopBroadcast();
    }

    function testDeployAdapter() external {}
}
