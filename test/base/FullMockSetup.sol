// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPlatform} from "../../src/core/Platform.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {Factory, IFactory} from "../../src/core/Factory.sol";
import {MockAggregatorV3Interface} from "../../src/test/MockAggregatorV3Interface.sol";
import {ChainlinkAdapter} from "../../src/adapters/ChainlinkAdapter.sol";
import {MockStrategy} from "../../src/test/MockStrategy.sol";
import {MockAmmAdapter} from "../../src/test/MockAmmAdapter.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {Swapper} from "../../src/core/Swapper.sol";
import {MockSetup} from "./MockSetup.sol";
import {HardWorker} from "../../src/core/HardWorker.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {RevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";
import {FeeTreasury} from "../../src/tokenomics/FeeTreasury.sol";
import {MetaVaultFactory} from "../../src/core/MetaVaultFactory.sol";

abstract contract FullMockSetup is MockSetup {
    Factory public factory;

    constructor() {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new PriceReader()));
        PriceReader priceReader = PriceReader(address(proxy));
        priceReader.initialize(address(platform));

        proxy = new Proxy();
        proxy.initProxy(address(new Factory()));
        factory = Factory(address(proxy));
        factory.initialize(address(platform));

        proxy = new Proxy();
        proxy.initProxy(address(new Swapper()));
        Swapper swapper = Swapper(address(proxy));
        swapper.initialize(address(platform));

        MockAggregatorV3Interface aggregatorV3InterfaceTokenA = new MockAggregatorV3Interface();
        MockAggregatorV3Interface aggregatorV3InterfaceTokenB = new MockAggregatorV3Interface();
        MockAggregatorV3Interface aggregatorV3InterfaceTokenC = new MockAggregatorV3Interface();
        aggregatorV3InterfaceTokenA.setAnswer(1e8);
        aggregatorV3InterfaceTokenA.setUpdatedAt(10);
        aggregatorV3InterfaceTokenB.setAnswer(2 * 1e8);
        aggregatorV3InterfaceTokenB.setUpdatedAt(10);
        aggregatorV3InterfaceTokenC.setAnswer(11 * 1e7); // 1.1 usd
        aggregatorV3InterfaceTokenC.setUpdatedAt(10);

        proxy = new Proxy();
        proxy.initProxy(address(new ChainlinkAdapter()));
        ChainlinkAdapter chainlinkAdapter = ChainlinkAdapter(address(proxy));
        chainlinkAdapter.initialize(address(platform));

        address[] memory assets = new address[](3);
        assets[0] = address(tokenA);
        assets[1] = address(tokenB);
        assets[2] = address(tokenC);
        address[] memory priceFeeds = new address[](3);
        priceFeeds[0] = address(aggregatorV3InterfaceTokenA);
        priceFeeds[1] = address(aggregatorV3InterfaceTokenB);
        priceFeeds[2] = address(aggregatorV3InterfaceTokenC);
        chainlinkAdapter.addPriceFeeds(assets, priceFeeds);
        priceReader.addAdapter(address(chainlinkAdapter));

        proxy = new Proxy();
        proxy.initProxy(address(new HardWorker()));
        HardWorker hardworker = HardWorker(payable(address(proxy)));
        hardworker.initialize(address(platform));

        proxy = new Proxy();
        proxy.initProxy(address(new RevenueRouter()));
        RevenueRouter revenueRouter = RevenueRouter(address(proxy));
        proxy = new Proxy();
        proxy.initProxy(address(new FeeTreasury()));
        FeeTreasury feeTreasury = FeeTreasury(address(proxy));
        feeTreasury.initialize(address(platform), platform.multisig());
        revenueRouter.initialize(address(platform), address(0), address(feeTreasury));

        proxy = new Proxy();
        proxy.initProxy(address(new MetaVaultFactory()));
        MetaVaultFactory metaVaultFactory = MetaVaultFactory(address(proxy));

        platform.setup(
            IPlatform.SetupAddresses({
                factory: address(factory),
                priceReader: address(priceReader),
                swapper: address(swapper),
                vaultManager: address(vaultManager),
                strategyLogic: address(strategyLogic),
                targetExchangeAsset: address(tokenA),
                hardWorker: address(hardworker),
                zap: address(0),
                revenueRouter: address(revenueRouter),
                metaVaultFactory: address(metaVaultFactory),
                vaultPriceOracle: address(0),
                recoveryContract: address(0)
            }),
            IPlatform.PlatformSettings({fee: 6_000})
        );

        MockAmmAdapter ammAdapter = new MockAmmAdapter(address(tokenA), address(tokenB));

        platform.addAmmAdapter("MOCKSWAP", address(ammAdapter));

        // setup factory
        factory.setVaultImplementation(VaultTypeLib.COMPOUNDING, address(vaultImplementation));
        MockStrategy strategyImplementation = new MockStrategy();
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.DEV,
                implementation: address(strategyImplementation),
                deployAllowed: true,
                upgradeAllowed: true,
                farming: false,
                tokenId: type(uint).max
            }),
            address(this)
        );
    }

    function testFullMockSetup() public {}
}
