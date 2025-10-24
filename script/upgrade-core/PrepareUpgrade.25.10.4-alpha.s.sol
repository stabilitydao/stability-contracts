// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Platform} from "../../src/core/Platform.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {UniswapV3Adapter} from "../../src/adapters/UniswapV3Adapter.sol";
import {SolidlyAdapter} from "../../src/adapters/SolidlyAdapter.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";
import {PriceAggregator} from "../../src/core/PriceAggregator.sol";
import {Recovery} from "../../src/tokenomics/Recovery.sol";

contract PrepareUpgrade25104alpha is Script {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Platform 1.6.3
        new Platform();

        // UniswapV3Adapter 1.1.0
        new UniswapV3Adapter();

        // SolidlyAdapter 1.0.1
        new SolidlyAdapter();

        // PriceReader 1.3.0
        new PriceReader();

        // Recovery 1.2.1
        new Recovery();

        // PriceAggregator 1.1.0
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new PriceAggregator()));
        PriceAggregator(address(proxy)).initialize(PLATFORM);

        vm.stopBroadcast();
    }

    function testPrepareUpgrade() external {}
}
