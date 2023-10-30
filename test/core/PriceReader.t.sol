// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Test, console, Vm} from "forge-std/Test.sol";
import "../../src/core/PriceReader.sol";
import "../../src/core/proxy/Proxy.sol";
import "../../src/test/MockAggregatorV3Interface.sol";
import "../../src/adapters/ChainlinkAdapter.sol";
import "../base/MockSetup.sol";

contract PriceReaderTest is Test, MockSetup {
    PriceReader public priceReader;
    ChainlinkAdapter public chainlinkAdapter;
    MockAggregatorV3Interface public aggregatorV3InterfaceTokenA;
    MockAggregatorV3Interface public aggregatorV3InterfaceTokenB;

    function setUp() public {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new PriceReader()));
        priceReader = PriceReader(address(proxy));

        proxy = new Proxy();
        proxy.initProxy(address(new ChainlinkAdapter()));
        chainlinkAdapter = ChainlinkAdapter(address(proxy));

        aggregatorV3InterfaceTokenA = new MockAggregatorV3Interface();
        aggregatorV3InterfaceTokenB = new MockAggregatorV3Interface();
        aggregatorV3InterfaceTokenA.setAnswer(1e8);
        aggregatorV3InterfaceTokenA.setUpdatedAt(10);
        aggregatorV3InterfaceTokenB.setAnswer(2 * 1e8);
        aggregatorV3InterfaceTokenB.setUpdatedAt(10);
    }

    function testOraclePrices() public {
        priceReader.initialize(address(platform));
        chainlinkAdapter.initialize(address(platform));

        priceReader.addAdapter(address(chainlinkAdapter));
        assertEq(priceReader.adaptersLength(), 1);
        address[] memory adapters = priceReader.adapters();
        assertEq(adapters[0], address(chainlinkAdapter));

        address[] memory assets = new address[](2);
        assets[0] = address(tokenA);
        assets[1] = address(tokenB);
        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = address(aggregatorV3InterfaceTokenA);
        priceFeeds[1] = address(aggregatorV3InterfaceTokenB);
        chainlinkAdapter.addPriceFeeds(assets, priceFeeds);

        // getPrice test
        (uint priceA, bool trustedA) = priceReader.getPrice(address(tokenA));
        (uint priceB, bool trustedB) = priceReader.getPrice(address(tokenB));
        vm.expectRevert();
        /*(uint priceUnavailable, bool trustedUnavailable) = */priceReader.getPrice(address(this));
        assertEq(priceA, 1e18);
        assertEq(trustedA, true);
        assertEq(priceB, 2 * 1e18);
        assertEq(trustedB, true);
//        assertEq(priceUnavailable, 0);
//        assertEq(trustedUnavailable, false);

        // getAssetsPrice test
        uint[] memory amounts = new uint[](2);
        amounts[0] = 500e18;
        amounts[1] = 300e6;
        (uint total, uint[] memory assetAmountPrice, bool trusted) = priceReader.getAssetsPrice(assets, amounts);
        assertEq(assetAmountPrice[0], 500e18);
        assertEq(assetAmountPrice[1], 300 * 2 * 1e18);
        assertEq(total, 1100 * 1e18);
        assertEq(trusted, true);

        priceReader.removeAdapter(address(chainlinkAdapter));

        // chainlink adapter test
        (address[] memory allAssets, uint[] memory allPrices,) = chainlinkAdapter.getAllPrices();
        assertEq(allAssets[1], address(tokenB));
        assertEq(allPrices[1], 2 * 1e18);
        address[] memory removeAssets = new address[](1);
        removeAssets[0] = address(tokenA);
        chainlinkAdapter.removePriceFeeds(removeAssets);
        allAssets = chainlinkAdapter.assets();
        assertEq(allAssets[0], address(tokenB));
        (uint price,) = chainlinkAdapter.getPrice(address(this));
        assertEq(price, 0);
    }
}