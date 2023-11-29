// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Test.sol";
import "../../src/core/proxy/Proxy.sol";
import "../../src/core/vaults/RMVault.sol";
import "../../src/core/vaults/RVault.sol";
import "../../src/core/Platform.sol";
import "../../src/core/Factory.sol";
import "../../src/core/VaultManager.sol";
import "../../src/core/StrategyLogic.sol";
import "../../src/core/vaults/CVault.sol";
import "../../src/core/PriceReader.sol";
import "../../src/core/AprOracle.sol";
import "../../src/core/Swapper.sol";
import "../../src/core/HardWorker.sol";
import "../../src/core/Zap.sol";
import "../../src/interfaces/IPlatform.sol";

library DeployLib {
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

    function deployPlatform(
        string memory version,
        address multisig,
        address buildingPermitToken,
        address buildingPayPerVaultToken,
        uint[] memory buildingPayPerVaultPrice,
        string memory networkName,
        bytes32 networkExtra,
        address targetExchangeAsset,
        address gelatoAutomate,
        uint gelatoMinBalance,
        uint gelatoDepositAmount
    ) internal returns (address) {
        DeployPlatformVars memory vars;
        vars.proxy = new Proxy();
        vars.proxy.initProxy(address(new Platform()));
        vars.platform = Platform(address(vars.proxy));
        vars.platform.initialize(multisig, version);

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
        vars.hardWorker.initialize(address(vars.platform), gelatoAutomate, gelatoMinBalance, gelatoDepositAmount);

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
                buildingPermitToken: buildingPermitToken,
                buildingPayPerVaultToken: buildingPayPerVaultToken,
                vaultManager: address(vars.vaultManager),
                strategyLogic: address(vars.strategyLogic),
                aprOracle: address(vars.aprOracle),
                targetExchangeAsset: targetExchangeAsset,
                hardWorker: address(vars.hardWorker),
                rebalancer: address(0),
                zap: address(vars.zap),
                bridge: address(0)
            }),
            IPlatform.PlatformSettings({
                networkName: networkName,
                networkExtra: networkExtra,
                fee: 6_000, // todo pass in args
                feeShareVaultManager: 30_000, // todo pass in args
                feeShareStrategyLogic: 30_000, // todo pass in args
                feeShareEcosystem: 0, // todo pass in args
                minInitialBoostPerDay: 30e18, // $30 // todo pass in args
                minInitialBoostDuration: 30 * 86400 // 30 days // todo pass in args
            })
        );

        // set all vault configs
        require(buildingPayPerVaultPrice.length == 3, "DeployLib: incorrect buildingPrice length");
        vars.factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: VaultTypeLib.COMPOUNDING,
                implementation: address(new CVault()),
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: buildingPayPerVaultPrice[0]
            })
        );
        vars.factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: VaultTypeLib.REWARDING,
                implementation: address(new RVault()),
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: buildingPayPerVaultPrice[1]
            })
        );
        vars.factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: VaultTypeLib.REWARDING_MANAGED,
                implementation: address(new RMVault()),
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: buildingPayPerVaultPrice[2]
            })
        );

        return address(vars.platform);
    }

    function logDeployAmmAdapters(address platform, bool showLog) external view {
        if (showLog) {
            (string[] memory ammAdaptersNames,) = IPlatform(platform).getAmmAdapters();
            console.log("Deployed AMM adapters:", CommonLib.implode(ammAdaptersNames, ", "));
        }
    }

    function logSetupSwapper(address platform, bool showLog) external view {
        if (showLog) {
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            IPriceReader priceReader = IPriceReader(IPlatform(platform).priceReader());
            address[] memory assets_ = swapper.bcAssets();
            string[] memory assetsStr = new string[](assets_.length);
            for (uint i; i < assets_.length; ++i) {
                (uint price,) = priceReader.getPrice(assets_[i]);
                assetsStr[i] = string.concat(IERC20Metadata(assets_[i]).symbol(), " ", CommonLib.formatUsdAmount(price));
            }
            console.log("Added blue chip pools to swapper with assets:", CommonLib.implode(assetsStr, ", "));

            assets_ = swapper.assets();
            assetsStr = new string[](assets_.length);
            for (uint i; i < assets_.length; ++i) {
                (uint price,) = priceReader.getPrice(assets_[i]);
                assetsStr[i] = string.concat(IERC20Metadata(assets_[i]).symbol(), " ", CommonLib.formatUsdAmount(price));
            }
            console.log("Added pools to swapper with assets:", CommonLib.implode(assetsStr, ", "));
        }
    }

    function logDeployAndSetupOracleAdapter(string memory name, address adapter, bool showLog) external view {
        if (showLog) {
            (address[] memory assets_, uint[] memory prices,) = IOracleAdapter(adapter).getAllPrices();
            string[] memory assetsStr = new string[](assets_.length);
            for (uint i; i < assets_.length; ++i) {
                assetsStr[i] =
                    string.concat(IERC20Metadata(assets_[i]).symbol(), " ", CommonLib.formatUsdAmount(prices[i]));
            }
            console.log(
                string.concat("Deployed ", name, " adapter. Added price feeds: ", CommonLib.implode(assetsStr, ", "))
            );
        }
    }

    function logAddedFarms(address factory, bool showLog) external view {
        if (showLog) {
            IFactory.Farm[] memory _farms = IFactory(factory).farms();
            console.log("Added farms:", _farms.length);
        }
    }

    function logSetupRewardTokens(address platform, bool showLog) external view {
        if (showLog) {
            IPlatform _platform = IPlatform(platform);
            address[] memory bbTokens = _platform.allowedBBTokens();
            address[] memory allowedRewardTokens = _platform.allowedBoostRewardTokens();
            string[] memory assetsStr = new string[](bbTokens.length);
            for (uint i; i < bbTokens.length; ++i) {
                assetsStr[i] = string.concat(
                    IERC20Metadata(bbTokens[i]).symbol(),
                    " - ",
                    CommonLib.u2s(_platform.allowedBBTokenVaults(bbTokens[i]))
                );
            }
            console.log(
                string.concat("Added allowed bbTokens vault building limit: ", CommonLib.implode(assetsStr, ", "))
            );
            assetsStr = new string[](allowedRewardTokens.length);
            for (uint i; i < allowedRewardTokens.length; ++i) {
                assetsStr[i] = IERC20Metadata(allowedRewardTokens[i]).symbol();
            }
            console.log(string.concat("Added allowed reward tokens: ", CommonLib.implode(assetsStr, ", ")));
        }
    }

    function logDeployStrategies(address platform, bool showLog) external view {
        if (showLog) {
            IPlatform _platform = IPlatform(platform);
            IFactory factory = IFactory(_platform.factory());
            bytes32[] memory hashes = factory.strategyLogicIdHashes();
            for (uint i; i < hashes.length; ++i) {
                IFactory.StrategyLogicConfig memory strategyConfig = factory.strategyLogicConfig(hashes[i]);
                console.log(
                    string.concat(
                        "Deployed strategy ", strategyConfig.id, " [", CommonLib.u2s(strategyConfig.tokenId), "]"
                    )
                );
            }
        }
    }

    function testDeployLib() external {}
}
