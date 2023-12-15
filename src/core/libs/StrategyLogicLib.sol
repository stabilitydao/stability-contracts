// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./CommonLib.sol";
import "../../interfaces/IStrategyLogic.sol";
import "../../interfaces/IPlatform.sol";

/// @dev Library for StrategyLogic's tokenURI generation with SVG image and other metadata
/// @author Alien Deployer (https://github.com/a17)
library StrategyLogicLib {
    struct TokenURIVars {
        uint h;
        uint strategyBlockHeight;
        uint step;
        string strategyColor;
        string strategyBgColor;
        string networkColor;
        string networkBgColor;
    }

    /// @dev Return SVG logo, name and description of VaultManager tokenId
    function tokenURI(
        IStrategyLogic.StrategyData memory strategyData,
        string memory platformVersion,
        IPlatform.PlatformSettings memory platformData
    ) external pure returns (string memory output) {
        //region ----- Setup vars -----
        TokenURIVars memory vars;
        vars.h = 40;
        vars.strategyBlockHeight = 730;
        vars.step = 40;
        vars.strategyColor = CommonLib.bToHex(abi.encodePacked(bytes3(strategyData.strategyExtra)));
        vars.strategyBgColor = CommonLib.bToHex(abi.encodePacked(bytes3(strategyData.strategyExtra << 8 * 3)));
        vars.networkColor = CommonLib.bToHex(abi.encodePacked(bytes3(platformData.networkExtra)));
        vars.networkBgColor = CommonLib.bToHex(abi.encodePacked(bytes3(platformData.networkExtra << 8 * 3)));
        output = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 900">';
        //endregion -- Setup vars -----

        //region ----- SVG logo -----
        //endregion -- SVG logo -----

        //region ----- Styles -----
        output = string.concat(output, "<style>");
        output = string.concat(output, ".base{font-weight: bold;font-family: sans-serif;}");
        output = string.concat(output, ".shortId{font-size:90px;font-family: monospace;}");
        output = string.concat(output, ".symbol{font-size:30px;}");
        output = string.concat(output, ".address{font-size:20px;}");
        output = string.concat(output, ".strategyTitle{font-size:38px;}");
        output = string.concat(output, ".strategy{font-size:30px;}");
        output = string.concat(output, ".param{font-size:26px;}");
        output = string.concat(output, ".value{font-size:26px;font-weight: bold;}");
        output = string.concat(output, ".platform{font-size:26px;}");
        output = string.concat(output, ".platform-param{font-size:20px;}");
        output = string.concat(output, ".platform-value{font-size:20px;font-weight: bold;}");
        output = string.concat(output, "</style>");
        //endregion -- Styles -----

        //region ----- Strategy -----
        vars.h = 328;
        output = string.concat(
            output,
            '<rect fill="#',
            vars.strategyBgColor,
            '" width="600" height="',
            _str(vars.strategyBlockHeight),
            '"/>'
        );

        // symbol width = 600 / 12 = 50
        string memory shortId = CommonLib.shortId(strategyData.strategyId);
        uint offset = 300 - bytes(shortId).length * 50 / 2;
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 ',
            _str(offset),
            " ",
            _str(vars.h),
            ')" fill="#',
            vars.strategyColor,
            '" class="base shortId">',
            CommonLib.shortId(strategyData.strategyId),
            "</text>"
        );

        vars.h += 328;
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 50 ',
            _str(vars.h),
            ')" fill="#',
            vars.strategyColor,
            '" class="strategyTitle base">Strategy #',
            _str(strategyData.strategyTokenId),
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
            strategyData.strategyId,
            "</text>"
        );
        //endregion -- Strategy -----

        //region ----- Platform -----
        vars.step = 30;
        output = string.concat(
            output,
            '<rect y="',
            _str(vars.strategyBlockHeight),
            '" fill="#',
            vars.networkBgColor,
            '" width="600" height="',
            _str(900 - vars.strategyBlockHeight),
            '"/>'
        );
        vars.h = vars.strategyBlockHeight + 20;
        vars.h += vars.step;
        output = string.concat(
            output,
            '<text transform="matrix(1 0 0 1 50 ',
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
            '" class="platform-param base">Strategy share</text><text transform="matrix(1 0 0 1 300 ',
            _str(vars.h),
            ')" fill="#',
            vars.networkColor,
            '" class="platform-value base">',
            CommonLib.formatApr(platformData.feeShareStrategyLogic),
            "</text>"
        );
        //endregion -- Platform -----

        //region ----- Name, description -----
        string memory name = string.concat("Strategy #", _str(strategyData.strategyTokenId));
        string memory description = string.concat("Strategy ", strategyData.strategyId);
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
