// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import "../../src/core/proxy/Proxy.sol";
import "../../src/core/Platform.sol";
import "../../src/core/Factory.sol";
import "../../src/core/VaultManager.sol";
import "../../src/core/StrategyLogic.sol";
import "../../src/core/PriceReader.sol";
import "../../src/core/Swapper.sol";
import "../../src/core/AprOracle.sol";
import "../../src/core/HardWorker.sol";
import "../../src/core/Zap.sol";
import "../../src/core/vaults/CVault.sol";
import "../../src/core/vaults/RVault.sol";
import "../../src/core/vaults/RMVault.sol";
import {IPlatformDeployer} from "../../src/interfaces/IPlatformDeployer.sol";

abstract contract DeployCore {
    struct DeployPlatformVars {
        Proxy proxy;
        Platform platform;
        Factory factory;
        VaultManager vaultManager;
        StrategyLogic strategyLogic;
        PriceReader priceReader;
        Swapper swapper;
        AprOracle aprOracle;
        HardWorker hardWorker;
        Zap zap;
    }

    function _deployCore(IPlatformDeployer.DeployPlatformParams memory p) internal returns (address) {
        DeployPlatformVars memory vars;
        vars.proxy = new Proxy();
        vars.proxy.initProxy(address(new Platform()));
        vars.platform = Platform(address(vars.proxy));
        vars.platform.initialize(p.multisig, p.version);

        // Factory
        vars.proxy = new Proxy();
        vars.proxy.initProxy(address(new Factory()));
        vars.factory = Factory(address(vars.proxy));
        vars.factory.initialize(address(vars.platform));

        // VaultManager
        vars.proxy = new Proxy();
        vars.proxy.initProxy(address(new VaultManager()));
        vars.vaultManager = VaultManager(address(vars.proxy));
        vars.vaultManager.init(address(vars.platform));

        // StrategyLogic
        vars.proxy = new Proxy();
        vars.proxy.initProxy(address(new StrategyLogic()));
        vars.strategyLogic = StrategyLogic(address(vars.proxy));
        vars.strategyLogic.init(address(vars.platform));

        // PriceReader
        vars.proxy = new Proxy();
        vars.proxy.initProxy(address(new PriceReader()));
        vars.priceReader = PriceReader(address(vars.proxy));
        vars.priceReader.initialize(address(vars.platform));

        // Swapper
        vars.proxy = new Proxy();
        vars.proxy.initProxy(address(new Swapper()));
        vars.swapper = Swapper(address(vars.proxy));
        vars.swapper.initialize(address(vars.platform));

        // AprOracle
        vars.proxy = new Proxy();
        vars.proxy.initProxy(address(new AprOracle()));
        vars.aprOracle = AprOracle(address(vars.proxy));
        vars.aprOracle.initialize(address(vars.platform));

        // HardWorker
        vars.proxy = new Proxy();
        vars.proxy.initProxy(address(new HardWorker()));
        vars.hardWorker = HardWorker(payable(address(vars.proxy)));
        vars.hardWorker.initialize(address(vars.platform), p.gelatoAutomate, p.gelatoMinBalance, p.gelatoDepositAmount);

        // Zap
        vars.proxy = new Proxy();
        vars.proxy.initProxy(address(new Zap()));
        vars.zap = Zap(payable(address(vars.proxy)));
        vars.zap.initialize(address(vars.platform));

        // setup platform
        vars.platform.setup(
            IPlatform.SetupAddresses({
                factory: address(vars.factory),
                priceReader: address(vars.priceReader),
                swapper: address(vars.swapper),
                buildingPermitToken: p.buildingPermitToken,
                buildingPayPerVaultToken: p.buildingPayPerVaultToken,
                vaultManager: address(vars.vaultManager),
                strategyLogic: address(vars.strategyLogic),
                aprOracle: address(vars.aprOracle),
                targetExchangeAsset: p.targetExchangeAsset,
                hardWorker: address(vars.hardWorker),
                rebalancer: address(0),
                zap: address(vars.zap),
                bridge: address(0)
            }),
            IPlatform.PlatformSettings({
                networkName: p.networkName,
                networkExtra: p.networkExtra,
                fee: p.fee,
                feeShareVaultManager: p.feeShareVaultManager,
                feeShareStrategyLogic: p.feeShareStrategyLogic,
                feeShareEcosystem: 0,
                minInitialBoostPerDay: 30e18, // $30
                minInitialBoostDuration: 30 * 86400 // 30 days
            })
        );

        return address(vars.platform);
    }

    function testDeployLib() external {}
}
