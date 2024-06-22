// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./CommonLib.sol";
import "./VaultTypeLib.sol";
import "../../interfaces/IPlatform.sol";
import "../../interfaces/IStrategy.sol";
import "../../interfaces/ISwapper.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IPriceReader.sol";
import "../../interfaces/IVault.sol";
import "../../interfaces/IRVault.sol";
import "../../interfaces/IVaultProxy.sol";
import "../../interfaces/IStrategyProxy.sol";

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
        if (assets.length == 1) {
            assetsSymbols = CommonLib.getSymbols(assets);
        } else {
            assetsSymbols = new string[](assets.length);
            for (uint i = 0; i < assets.length; ++i) {
                string memory aliasName = factory.getAliasName(assets[i]);
                if (bytes(aliasName).length == 0) {
                    aliasName = IERC20Metadata(assets[i]).symbol();
                }
                assetsSymbols[i] = aliasName;
            }
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
