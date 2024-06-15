// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

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

library LogDeployLib {
    function logDeployAmmAdapters(address platform, bool showLog) internal view {
        if (showLog) {
            (string[] memory ammAdaptersNames,) = IPlatform(platform).getAmmAdapters();
            console.log("Deployed AMM adapters:", CommonLib.implode(ammAdaptersNames, ", "));
        }
    }

    function logSetupSwapper(address platform, bool showLog) internal view {
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
                // using try..catch because on old forking blocks assets and pools can be not available
                try priceReader.getPrice(assets_[i]) returns (uint price, bool) {
                    assetsStr[i] =
                        string.concat(IERC20Metadata(assets_[i]).symbol(), " ", CommonLib.formatUsdAmount(price));
                    assetsStr[i] =
                        string.concat(IERC20Metadata(assets_[i]).symbol(), " ", CommonLib.formatUsdAmount(price));
                } catch {}
            }
            console.log("Added pools to swapper with assets:", CommonLib.implode(assetsStr, ", "));
        }
    }

    function logDeployAndSetupOracleAdapter(string memory name, address adapter, bool showLog) internal view {
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

    function logAddedFarms(address factory, bool showLog) internal view {
        if (showLog) {
            IFactory.Farm[] memory _farms = IFactory(factory).farms();
            console.log("Added farms:", _farms.length);
        }
    }

    function logSetupRewardTokens(address platform, bool showLog) internal view {
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

    function logDeployStrategies(address platform, bool showLog) internal view {
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
