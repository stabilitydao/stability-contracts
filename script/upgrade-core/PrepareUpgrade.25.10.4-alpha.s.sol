// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Platform} from "../../src/core/Platform.sol";
// import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {UniswapV3Adapter} from "../../src/adapters/UniswapV3Adapter.sol";
import {SolidlyAdapter} from "../../src/adapters/SolidlyAdapter.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";
import {PriceAggregator} from "../../src/core/PriceAggregator.sol";
import {Recovery} from "../../src/tokenomics/Recovery.sol";
import {ChainlinkMinimal2V3Adapter} from "../../src/adapters/ChainlinkMinimal2V3Adapter.sol";
import {PriceOracle} from "../../src/periphery/PriceOracle.sol";

contract PrepareUpgrade25104alpha is Script {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;

    address public constant PRICE_AGGREGATOR_SONIC = 0x3137a6498D03dF485D75aF9a866BbE73FD1124EA;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Platform 1.6.3
        new Platform();

        // UniswapV3Adapter 1.1.0
        new UniswapV3Adapter();

        // SolidlyAdapter 1.1.0
        new SolidlyAdapter();

        // PriceReader 1.3.0
        new PriceReader();

        // Recovery 1.2.1
        new Recovery();

        // PriceAggregator 1.1.0
        new PriceAggregator();

        // Price oracle + ChainlinkMinimal2V3Adapter for the oracle
        PriceOracle priceOracle = new PriceOracle(SonicConstantsLib.TOKEN_STBL, PRICE_AGGREGATOR_SONIC);
        new ChainlinkMinimal2V3Adapter(address(priceOracle));

        //        Proxy proxy = new Proxy();
        //        proxy.initProxy(address(new PriceAggregator()));
        //        PriceAggregator(address(proxy)).initialize(PLATFORM);

        vm.stopBroadcast();
    }

    function testPrepareUpgrade() external {}
}
