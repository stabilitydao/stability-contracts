// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Test.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPriceReader} from "../../src/core/PriceReader.sol";
import {ISwapper} from "../../src/core/Swapper.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IOracleAdapter} from "../../src/interfaces/IOracleAdapter.sol";

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
