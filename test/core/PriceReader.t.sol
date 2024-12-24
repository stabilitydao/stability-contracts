// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console, Vm} from "forge-std/Test.sol";
import "../../src/core/PriceReader.sol";
import "../../src/core/proxy/Proxy.sol";
import "../../src/test/MockAggregatorV3Interface.sol";
import "../../src/adapters/ChainlinkAdapter.sol";
import "../base/MockSetup.sol";
import "../../src/test/MockAmmAdapter.sol";
import "../../src/adapters/libs/AmmAdapterIdLib.sol";
import "../../src/adapters/UniswapV3Adapter.sol";
import "../../src/core/Swapper.sol";
import "../../chains/PolygonLib.sol";

contract PriceReaderTest is Test, MockSetup {
    Swapper public swapper;
    PriceReader public priceReader;
    ChainlinkAdapter public chainlinkAdapter;
    UniswapV3Adapter public uniswapV3Adapter;
    MockAggregatorV3Interface public aggregatorV3InterfaceTokenA;
    MockAggregatorV3Interface public aggregatorV3InterfaceTokenB;
    MockAggregatorV3Interface public aggregatorV3InterfaceTokenD;

    function setUp() public {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new PriceReader()));
        priceReader = PriceReader(address(proxy));

        proxy = new Proxy();
        proxy.initProxy(address(new ChainlinkAdapter()));
        chainlinkAdapter = ChainlinkAdapter(address(proxy));

        proxy = new Proxy();
        proxy.initProxy(address(new Platform()));
        platform = Platform(address(proxy));
        platform.initialize(address(this), "23.11.0-dev");

        proxy = new Proxy();
        proxy.initProxy(address(new Swapper()));
        swapper = Swapper(address(proxy));
        swapper.initialize(address(platform));

        //add AmmAdapterIdLib's id adapter
        uniswapV3Adapter = new UniswapV3Adapter();
        platform.addAmmAdapter(AmmAdapterIdLib.UNISWAPV3, address(uniswapV3Adapter));

        // deploy and init adapters
        proxy = new Proxy();
        proxy.initProxy(address(new UniswapV3Adapter()));
        uniswapV3Adapter = UniswapV3Adapter(address(proxy));
        uniswapV3Adapter.init(address(platform));

        aggregatorV3InterfaceTokenA = new MockAggregatorV3Interface();
        aggregatorV3InterfaceTokenB = new MockAggregatorV3Interface();
        aggregatorV3InterfaceTokenD = new MockAggregatorV3Interface();
        aggregatorV3InterfaceTokenA.setAnswer(1e8);
        aggregatorV3InterfaceTokenA.setUpdatedAt(10);
        aggregatorV3InterfaceTokenB.setAnswer(2 * 1e8);
        aggregatorV3InterfaceTokenB.setUpdatedAt(10);
        aggregatorV3InterfaceTokenD.setAnswer(3 * 1e8);
        aggregatorV3InterfaceTokenD.setUpdatedAt(10);
    }

    function testOraclePrices() public {
        platform.setup(
            IPlatform.SetupAddresses({
                factory: address(1),
                priceReader: address(priceReader),
                swapper: address(swapper),
                buildingPermitToken: address(4),
                buildingPayPerVaultToken: address(5),
                vaultManager: address(6),
                strategyLogic: address(7),
                aprOracle: address(8),
                targetExchangeAsset: address(9),
                hardWorker: address(10),
                rebalancer: address(0),
                zap: address(11),
                bridge: address(0)
            }),
            IPlatform.PlatformSettings({
                networkName: "Localhost Ethereum",
                networkExtra: CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x7746d7), bytes3(0x040206))),
                fee: 6_000,
                feeShareVaultManager: 30_000,
                feeShareStrategyLogic: 30_000,
                feeShareEcosystem: 0,
                minInitialBoostPerDay: 30e18, // $30
                minInitialBoostDuration: 30 * 86400 // 30 days
            })
        );

        MockAmmAdapter dexAdapter = new MockAmmAdapter(address(tokenE), address(tokenD));

        ISwapper.PoolData[] memory pools = new ISwapper.PoolData[](1);
        pools[0] = ISwapper.PoolData({
            pool: PolygonLib.POOL_UNISWAPV3_USDCe_USDT_100,
            ammAdapter: address(dexAdapter),
            tokenIn: address(tokenE),
            tokenOut: address(tokenD)
        });

        swapper.addPools(pools, false);

        priceReader.initialize(address(platform));
        chainlinkAdapter.initialize(address(platform));

        priceReader.addAdapter(address(chainlinkAdapter));
        vm.expectRevert(abi.encodeWithSelector(IControllable.AlreadyExist.selector));
        priceReader.addAdapter(address(chainlinkAdapter));
        assertEq(priceReader.adaptersLength(), 1);
        address[] memory adapters = priceReader.adapters();
        assertEq(adapters[0], address(chainlinkAdapter));

        address[] memory assets = new address[](3);
        assets[0] = address(tokenA);
        assets[1] = address(tokenB);
        assets[2] = address(tokenD);
        address[] memory priceFeeds = new address[](3);
        priceFeeds[0] = address(aggregatorV3InterfaceTokenA);
        priceFeeds[1] = address(aggregatorV3InterfaceTokenB);
        priceFeeds[2] = address(aggregatorV3InterfaceTokenD);

        address[] memory fakeAssets = new address[](2);
        fakeAssets[0] = address(tokenA);
        fakeAssets[1] = address(tokenA);
        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        chainlinkAdapter.addPriceFeeds(assets, fakeAssets);

        address[] memory sameAssets = new address[](3);
        sameAssets[0] = address(tokenA);
        sameAssets[1] = address(tokenA);
        sameAssets[2] = address(tokenA);
        vm.expectRevert(IControllable.AlreadyExist.selector);
        chainlinkAdapter.addPriceFeeds(sameAssets, priceFeeds);

        chainlinkAdapter.addPriceFeeds(assets, priceFeeds);

        {
            // getPrice test
            (uint priceA, bool trustedA) = priceReader.getPrice(address(tokenA));
            (uint priceB, bool trustedB) = priceReader.getPrice(address(tokenB));
            (uint priceD, bool trustedD) = priceReader.getPrice(address(tokenD));
            (uint priceE, bool trustedE) = priceReader.getPrice(address(tokenE));
            (uint _zero, bool _false) = priceReader.getPrice(address(this));
            assertEq(priceA, 1e18, "A0");
            assertEq(trustedA, true);
            assertEq(priceB, 2 * 1e18, "A1");
            assertEq(trustedB, true);
            assertEq(priceD, 3 * 1e18, "A2");
            assertEq(trustedD, true);
            assertEq(priceE, 3 * 2e12, "A3");
            assertEq(trustedE, false);
            assertEq(_zero, 0);
            assertEq(_false, false);
        }

        // getAssetsPrice test
        uint[] memory amounts = new uint[](3);
        amounts[0] = 500e18;
        amounts[1] = 300e6;
        amounts[2] = 1e24;
        (uint total, uint[] memory assetAmountPrice,, bool trusted) = priceReader.getAssetsPrice(assets, amounts);
        assertEq(assetAmountPrice[0], 500e18);
        assertEq(assetAmountPrice[1], 300 * 2 * 1e18);
        assertEq(assetAmountPrice[2], 3 * 1e18);
        assertEq(total, 1103 * 1e18);
        assertEq(trusted, true);

        priceReader.removeAdapter(address(chainlinkAdapter));
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotExist.selector));
        priceReader.removeAdapter(address(chainlinkAdapter));

        // chainlink adapter test
        (address[] memory allAssets, uint[] memory allPrices,) = chainlinkAdapter.getAllPrices();
        assertEq(allAssets[1], address(tokenB));
        assertEq(allPrices[1], 2 * 1e18);
        address[] memory removeAssets = new address[](1);
        removeAssets[0] = address(tokenA);
        address[] memory removeNotExistingAsset = new address[](1);
        removeNotExistingAsset[0] = address(123);
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotExist.selector));
        chainlinkAdapter.removePriceFeeds(removeNotExistingAsset);
        chainlinkAdapter.removePriceFeeds(removeAssets);
        allAssets = chainlinkAdapter.assets();
        assertEq(allAssets[0], address(tokenD));
        (uint price,) = chainlinkAdapter.getPrice(address(this));
        assertEq(price, 0);
    }
}
