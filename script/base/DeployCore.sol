// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Test.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {Platform, IPlatform} from "../../src/core/Platform.sol";
import {Factory} from "../../src/core/Factory.sol";
import {VaultManager} from "../../src/core/VaultManager.sol";
import {StrategyLogic} from "../../src/core/StrategyLogic.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";
import {Swapper} from "../../src/core/Swapper.sol";
import {AprOracle} from "../../src/core/AprOracle.sol";
import {HardWorker} from "../../src/core/HardWorker.sol";
import {Zap} from "../../src/core/Zap.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {RVault} from "../../src/core/vaults/RVault.sol";
import {RMVault} from "../../src/core/vaults/RMVault.sol";
import {IPlatformDeployer} from "../../src/interfaces/IPlatformDeployer.sol";
import {RevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";
import {FeeTreasury} from "../../src/tokenomics/FeeTreasury.sol";

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
        RevenueRouter revenueRouter;
        FeeTreasury feeTreasury;
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

        // RevenueRouter + FeeTreasury
        vars.proxy = new Proxy();
        vars.proxy.initProxy(address(new FeeTreasury()));
        vars.feeTreasury = FeeTreasury(address(vars.proxy));
        vars.feeTreasury.initialize(address(vars.platform));
        vars.proxy = new Proxy();
        vars.proxy.initProxy(address(new RevenueRouter()));
        vars.revenueRouter = RevenueRouter(address(vars.proxy));
        vars.revenueRouter.initialize(address(vars.platform), address(0), address(vars.feeTreasury));

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
                zap: address(vars.zap),
                revenueRouter: address(vars.revenueRouter)
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
