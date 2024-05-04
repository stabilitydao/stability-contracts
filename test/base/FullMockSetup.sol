// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Platform} from "../../src/core/Platform.sol";
import "../../src/core/PriceReader.sol";
import "../../src/core/proxy/Proxy.sol";
import "../../src/test/MockERC20.sol";
import "../../src/core/Factory.sol";
import "../../src/test/MockAggregatorV3Interface.sol";
import "../../src/adapters/ChainlinkAdapter.sol";
import "../../src/test/MockStrategy.sol";
import "../../src/test/MockAmmAdapter.sol";
import "../../src/strategies/libs/StrategyIdLib.sol";
import "../../src/core/Swapper.sol";
import "../../src/test/MockERC721.sol";
import "./MockSetup.sol";
import "../../src/core/AprOracle.sol";
import "../../src/core/HardWorker.sol";

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
        proxy.initProxy(address(new AprOracle()));
        AprOracle aprOracle = AprOracle(address(proxy));
        aprOracle.initialize(address(platform));

        proxy = new Proxy();
        proxy.initProxy(address(new HardWorker()));
        HardWorker hardworker = HardWorker(payable(address(proxy)));
        hardworker.initialize(address(platform), address(0), 0, 0);

        platform.setup(
            IPlatform.SetupAddresses({
                factory: address(factory),
                priceReader: address(priceReader),
                swapper: address(swapper),
                buildingPermitToken: address(builderPermitToken),
                buildingPayPerVaultToken: address(builderPayPerVaultToken),
                vaultManager: address(vaultManager),
                strategyLogic: address(strategyLogic),
                aprOracle: address(aprOracle),
                targetExchangeAsset: address(tokenA),
                hardWorker: address(hardworker),
                rebalancer: address(0),
                zap: address(0),
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

        MockAmmAdapter ammAdapter = new MockAmmAdapter(address(tokenA), address(tokenB));

        platform.addAmmAdapter("MOCKSWAP", address(ammAdapter));

        // setup factory
        uint buildingPayPerVaultPrice = 1e16;
        factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: VaultTypeLib.COMPOUNDING,
                implementation: address(vaultImplementation),
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: buildingPayPerVaultPrice
            })
        );
        factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: VaultTypeLib.REWARDING,
                implementation: address(rVaultImplementation),
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: buildingPayPerVaultPrice
            })
        );
        factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: VaultTypeLib.REWARDING_MANAGED,
                implementation: address(rmVaultImplementation),
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: buildingPayPerVaultPrice
            })
        );
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
