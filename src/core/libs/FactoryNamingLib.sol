// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./CommonLib.sol";
import "./VaultTypeLib.sol";
import "../../interfaces/IPlatform.sol";
import "../../interfaces/IStrategy.sol";
import "../../interfaces/IFactory.sol";

library FactoryNamingLib {
    function getStrategyData(
        string memory vaultType,
        address strategyAddress,
        address bbAsset,
        address platform
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
        IFactory factory = IFactory(IPlatform(platform).factory());
        strategyId = IStrategy(strategyAddress).strategyLogicId();
        assets = IStrategy(strategyAddress).assets();

        // Determine the length of the assets array
        uint assetsLength = assets.length;

        // Initialize assetsSymbols based on the length of assets
        assetsSymbols = new string[](assetsLength);

        for (uint i = 0; i < assetsLength; ++i) {
            // Use a ternary operator to determine the symbol to use
            string memory symbol = assets.length == 1
                ? CommonLib.getSymbols(assets)[0]
                : (
                    bytes(factory.getAliasName(assets[i])).length != 0
                        ? factory.getAliasName(assets[i])
                        : IERC20Metadata(assets[i]).symbol()
                );
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
        if (CommonLib.eq(vaultType, VaultTypeLib.REWARDING)) {
            prefix = "R";
        }
        if (CommonLib.eq(vaultType, VaultTypeLib.REWARDING_MANAGED)) {
            prefix = "M";
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
