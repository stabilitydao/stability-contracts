// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {CommonLib} from "./CommonLib.sol";
import {VaultTypeLib} from "./VaultTypeLib.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {IFactory} from "../../interfaces/IFactory.sol";

library FactoryNamingLib {
    function getStrategyData(
        string memory vaultType,
        address strategyAddress,
        address bbAsset,
        address
    )
        public
        view
        returns (
            string memory strategyId,
            address[] memory assets,
            string[] memory assetsSymbols,
            string memory specificName,
            string memory vaultSymbol
        )
    {
        strategyId = IStrategy(strategyAddress).strategyLogicId();
        assets = IStrategy(strategyAddress).assets();

        // Determine the length of the assets array
        uint assetsLength = assets.length;

        // Initialize assetsSymbols based on the length of assets
        assetsSymbols = new string[](assetsLength);

        for (uint i = 0; i < assetsLength; ++i) {
            // Use a ternary operator to determine the symbol to use
            string memory symbol =
                assets.length == 1 ? CommonLib.getSymbols(assets)[0] : IERC20Metadata(assets[i]).symbol();
            assetsSymbols[i] = symbol;
        }
        bool showSpecificInSymbol;
        (specificName, showSpecificInSymbol) = IStrategy(strategyAddress).getSpecificName();

        string memory bbAssetSymbol = bbAsset == address(0) ? "" : IERC20Metadata(bbAsset).symbol();

        vaultSymbol = _getShortSymbol(
            vaultType,
            strategyId,
            CommonLib.implode(assetsSymbols, ""),
            showSpecificInSymbol ? specificName : "",
            bbAssetSymbol
        );
    }

    function _getShortSymbol(
        string memory vaultType,
        string memory strategyLogicId,
        string memory symbols,
        string memory specificName,
        string memory bbAssetSymbol
    ) internal pure returns (string memory) {
        bytes memory vaultTypeBytes = bytes(vaultType);
        string memory prefix = "v";
        if (vaultTypeBytes[0] == "C") {
            prefix = "C";
        }
        string memory bbAssetStr = bytes(bbAssetSymbol).length > 0 ? string.concat("-", bbAssetSymbol) : "";
        return string.concat(
            prefix,
            "-",
            symbols,
            bbAssetStr,
            "-",
            CommonLib.shortId(strategyLogicId),
            bytes(specificName).length > 0 ? CommonLib.shortId(specificName) : ""
        );
    }
}
