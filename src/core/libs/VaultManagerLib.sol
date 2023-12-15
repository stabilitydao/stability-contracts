// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./CommonLib.sol";
import "../../interfaces/IVaultManager.sol";
import "../../interfaces/IPlatform.sol";

/// @dev Library for VaultManager's tokenURI generation with SVG image and other metadata
library VaultManagerLib {
    struct TokenURIVars {
        uint h;
        uint vaultBlockHeight;
        uint platformBlockHeight;
        uint step;
        string vaultColor;
        string vaultBgColor;
        string strategyColor;
        string strategyBgColor;
        string networkColor;
        string networkBgColor;
    }

    /// @dev Return SVG logo, name and description of VaultManager tokenId
    function tokenURI(
        IVaultManager.VaultData memory vaultData,
        string memory platformVersion,
        IPlatform.PlatformSettings memory platformData
    ) external pure returns (string memory output) {
        //region ----- Setup vars -----
        TokenURIVars memory vars;
        vars.h = 40;
        vars.vaultBlockHeight = 470;
        vars.platformBlockHeight = 170;
        vars.step = 40;
        vars.vaultColor = CommonLib.bToHex(abi.encodePacked(bytes3(vaultData.vaultExtra)));
        vars.vaultBgColor = CommonLib.bToHex(abi.encodePacked(bytes3(vaultData.vaultExtra << 8 * 3)));
        vars.strategyColor = CommonLib.bToHex(abi.encodePacked(bytes3(vaultData.strategyExtra)));
        vars.strategyBgColor = CommonLib.bToHex(abi.encodePacked(bytes3(vaultData.strategyExtra << 8 * 3)));
        vars.networkColor = CommonLib.bToHex(abi.encodePacked(bytes3(platformData.networkExtra)));
        vars.networkBgColor = CommonLib.bToHex(abi.encodePacked(bytes3(platformData.networkExtra << 8 * 3)));
        output = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 900">';
        //endregion -- Setup vars -----

        //region ----- SVG logo -----
        //endregion -- SVG logo -----

        //region ----- Styles -----
        output = string.concat(output, "<style>");
        output = string.concat(output, ".base{font-weight: bold;font-family: sans-serif;}");
        output = string.concat(output, ".title{font-size:46px;}");
        output = string.concat(output, ".symbol{font-size:30px;}");
        output = string.concat(output, ".address{font-size:20px;}");
        output = string.concat(output, ".strategyTitle{font-size:34px;}");
        output = string.concat(output, ".strategy{font-size:30px;}");
        output = string.concat(output, ".param{font-size:26px;}");
        output = string.concat(output, ".value{font-size:26px;font-weight: bold;}");
        output = string.concat(output, ".platform{font-size:26px;}");
        output = string.concat(output, ".platform-param{font-size:20px;}");
        output = string.concat(output, ".platform-value{font-size:20px;font-weight: bold;}");
        output = string.concat(output, "</style>");
        //endregion -- Styles -----

        //region ----- Vault -----
        vars.h += vars.step;
        output = string.concat(
            output, '<rect fill="#', vars.vaultBgColor, '" width="600" height="', _str(vars.vaultBlockHeight), '"/>'
        );
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 50 ',
            _str(vars.h),
            ')" fill="#',
            vars.vaultColor,
            '" class="title base">Vault #',
            _str(vaultData.tokenId),
            "</text>"
        );
        vars.h += vars.step + 6;
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 50 ',
            _str(vars.h),
            ')" fill="#',
            vars.vaultColor,
            '" class="symbol base">',
            vaultData.symbol,
            "</text>"
        );
        vars.h += vars.step - 4;
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 50 ',
            _str(vars.h),
            ')" fill="#',
            vars.vaultColor,
            '" class="address base">',
            Strings.toHexString(vaultData.vault),
            "</text>"
        );
        vars.h += vars.step;
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 50 ',
            _str(vars.h),
            ')" fill="#',
            vars.vaultColor,
            '" class="param base">Type</text><text transform="matrix(1 0 0 1 300 ',
            _str(vars.h),
            ')" fill="#',
            vars.vaultColor,
            '" class="value base">',
            vaultData.vaultType,
            "</text>"
        );
        vars.h += vars.step;
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 50 ',
            _str(vars.h),
            ')" fill="#',
            vars.vaultColor,
            '" class="param base">Assets</text><text transform="matrix(1 0 0 1 300 ',
            _str(vars.h),
            ')" fill="#',
            vars.vaultColor,
            '" class="value base">',
            CommonLib.implode(vaultData.assetsSymbols, ", "),
            "</text>"
        );
        if (vaultData.rewardAssetsSymbols.length > 0) {
            vars.h += vars.step;
            output = string.concat(
                output,
                '<text transform="matrix(1 0 0 1 50 ',
                _str(vars.h),
                ')" fill="#',
                vars.vaultColor,
                '" class="param base">Buy-back</text><text transform="matrix(1 0 0 1 300 ',
                _str(vars.h),
                ')" fill="#',
                vars.vaultColor,
                '" class="value base">',
                vaultData.rewardAssetsSymbols[0],
                "</text>"
            );
            vars.h += vars.step;
            output = string.concat(
                output,
                '<text transform="matrix(1 0 0 1 50 ',
                _str(vars.h),
                ')" fill="#',
                vars.vaultColor,
                '" class="param base">Boost</text><text transform="matrix(1 0 0 1 300 ',
                _str(vars.h),
                ')" fill="#',
                vars.vaultColor,
                '" class="value base">',
                CommonLib.implode(vaultData.rewardAssetsSymbols, ", "),
                "</text>"
            );
        }
        vars.h += vars.step;
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 50 ',
            _str(vars.h),
            ')" fill="#',
            vars.vaultColor,
            '" class="param base">APR</text><text transform="matrix(1 0 0 1 300 ',
            _str(vars.h),
            ')" fill="#',
            vars.vaultColor,
            '" class="value base">',
            CommonLib.formatApr(vaultData.totalApr),
            "</text>"
        );
        vars.h += vars.step;
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 50 ',
            _str(vars.h),
            ')" fill="#',
            vars.vaultColor,
            '" class="param base">Share price</text><text transform="matrix(1 0 0 1 300 ',
            _str(vars.h),
            ')" fill="#',
            vars.vaultColor,
            '" class="value base">',
            CommonLib.formatUsdAmount(vaultData.sharePrice),
            "</text>"
        );
        vars.h += vars.step;
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 50 ',
            _str(vars.h),
            ')" fill="#',
            vars.vaultColor,
            '" class="param base">TVL</text><text transform="matrix(1 0 0 1 300 ',
            _str(vars.h),
            ')" fill="#',
            vars.vaultColor,
            '" class="value base">',
            CommonLib.formatUsdAmount(vaultData.tvl),
            "</text>"
        );
        //endregion -- Vault -----

        //region ----- Strategy -----
        uint strategyBlockHeight = 900 - vars.vaultBlockHeight - vars.platformBlockHeight;
        vars.h = vars.vaultBlockHeight + 15;
        output = string.concat(
            output,
            '<rect y="',
            _str(vars.vaultBlockHeight),
            '" fill="#',
            vars.strategyBgColor,
            '" width="600" height="',
            _str(strategyBlockHeight),
            '"/>'
        );
        vars.h += vars.step;
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 50 ',
            _str(vars.h),
            ')" fill="#',
            vars.strategyColor,
            '" class="strategyTitle base">Strategy #',
            _str(vaultData.strategyTokenId),
            "</text>"
        );
        vars.h += vars.step + 4;
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 50 ',
            _str(vars.h),
            ')" fill="#',
            vars.strategyColor,
            '" class="strategy base">',
            vaultData.strategyId,
            "</text>"
        );
        if (bytes(vaultData.strategySpecific).length > 0) {
            vars.h += vars.step;
            output = string.concat(
                output,
                '<text transform="matrix(1 0 0 1 50 ',
                _str(vars.h),
                ')" fill="#',
                vars.strategyColor,
                '" class="param base">Specific</text><text transform="matrix(1 0 0 1 300 ',
                _str(vars.h),
                ')" fill="#',
                vars.strategyColor,
                '" class="value base">',
                vaultData.strategySpecific,
                "</text>"
            );
        }
        vars.h += vars.step;
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 50 ',
            _str(vars.h),
            ')" fill="#',
            vars.strategyColor,
            '" class="param base">Strategy APR</text><text transform="matrix(1 0 0 1 300 ',
            _str(vars.h),
            ')" fill="#',
            vars.strategyColor,
            '" class="value base">',
            CommonLib.formatApr(vaultData.strategyApr),
            "</text>"
        );
        //endregion -- Strategy -----

        //region ----- Platform -----
        vars.step = 30;
        output = string.concat(
            output,
            '<rect y="',
            _str(vars.vaultBlockHeight + strategyBlockHeight),
            '" fill="#',
            vars.networkBgColor,
            '" width="600" height="',
            _str(vars.platformBlockHeight),
            '"/>'
        );
        vars.h = vars.vaultBlockHeight + strategyBlockHeight + 20;
        output = string.concat(output, '<g transform="translate(50,', _str(vars.h + 8), ')">');
        output = string.concat(
            output, '<polygon style="fill:#6466e9;" points="24,5.6 12.8,0 1.6,5.6 1.6,20 12.8,25.6 24,20 "/>'
        );
        output = string.concat(
            output, '<polygon style="fill:#36309d;" points="12.8,11.2 1.6,5.6 1.6,20 12.8,25.6 24,20 24,5.6 "/>'
        );
        output = string.concat(output, '<polygon style="fill:#201c62;" points="12.8,11.2 12.8,25.6 24,20 24,5.6 "/>');
        output = string.concat(output, "</g>");

        vars.h += vars.step;

        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 80 ',
            _str(vars.h),
            ')" fill="#',
            vars.networkColor,
            '" class="platform base">Stability Platform ',
            platformVersion,
            "</text>"
        );
        vars.h += vars.step;
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 50 ',
            _str(vars.h),
            ')" fill="#',
            vars.networkColor,
            '" class="platform-param base">Network</text><text transform="matrix(1 0 0 1 300 ',
            _str(vars.h),
            ')" fill="#',
            vars.networkColor,
            '" class="platform-value base">',
            platformData.networkName,
            "</text>"
        );
        vars.h += vars.step;
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 50 ',
            _str(vars.h),
            ')" fill="#',
            vars.networkColor,
            '" class="platform-param base">Revenue fee</text><text transform="matrix(1 0 0 1 300 ',
            _str(vars.h),
            ')" fill="#',
            vars.networkColor,
            '" class="platform-value base">',
            CommonLib.formatApr(platformData.fee),
            "</text>"
        );
        vars.h += vars.step;
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 50 ',
            _str(vars.h),
            ')" fill="#',
            vars.networkColor,
            '" class="platform-param base">Manager share</text><text transform="matrix(1 0 0 1 300 ',
            _str(vars.h),
            ')" fill="#',
            vars.networkColor,
            '" class="platform-value base">',
            CommonLib.formatApr(platformData.feeShareVaultManager),
            "</text>"
        );
        //endregion -- Platform -----

        //region ----- Name, description -----
        string memory name = string.concat("Vault #", _str(vaultData.tokenId));
        string memory description = string.concat("Vault ", vaultData.name);
        //endregion -- Name, description -----

        //region ----- Encoding -----
        output = string.concat(output, "</svg>");
        string memory json = Base64.encode(
            bytes(
                string.concat(
                    '{"name": "',
                    name,
                    '", "description": "',
                    description,
                    '", "image": "data:image/svg+xml;base64,',
                    Base64.encode(bytes(output)),
                    '"}'
                )
            )
        );
        output = string.concat("data:application/json;base64,", json);
        //endregion -- Encoding -----
    }

    function _str(uint num) internal pure returns (string memory) {
        return Strings.toString(num);
    }
}
