// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./ConstantsLib.sol";

library CommonLib {
    function filterAddresses(
        address[] memory addresses,
        address addressToRemove
    ) external pure returns (address[] memory filteredAddresses) {
        uint len = addresses.length;
        uint newLen;
        // nosemgrep
        for (uint i; i < len; ++i) {
            if (addresses[i] != addressToRemove) {
                ++newLen;
            }
        }
        filteredAddresses = new address[](newLen);
        uint k;
        // nosemgrep
        for (uint i; i < len; ++i) {
            if (addresses[i] != addressToRemove) {
                filteredAddresses[k] = addresses[i];
                ++k;
            }
        }
    }

    function formatUsdAmount(uint amount) external pure returns (string memory formattedPrice) {
        uint dollars = amount / 10 ** 18;
        string memory priceStr;
        if (dollars >= 1000) {
            uint kDollars = dollars / 1000;
            uint kDollarsFraction = (dollars - kDollars * 1000) / 10;
            string memory delimiter = ".";
            if (kDollarsFraction < 10) {
                delimiter = ".0";
            }
            priceStr = string.concat(Strings.toString(kDollars), delimiter, Strings.toString(kDollarsFraction), "k");
        } else if (dollars >= 100) {
            priceStr = Strings.toString(dollars);
        } else {
            uint dollarsFraction = (amount - dollars * 10 ** 18) / 10 ** 14;
            if (dollarsFraction > 0) {
                string memory dollarsFractionDelimiter = ".";
                if (dollarsFraction < 10) {
                    dollarsFractionDelimiter = ".000";
                } else if (dollarsFraction < 100) {
                    dollarsFractionDelimiter = ".00";
                } else if (dollarsFraction < 1000) {
                    dollarsFractionDelimiter = ".0";
                }
                priceStr = string.concat(
                    Strings.toString(dollars), dollarsFractionDelimiter, Strings.toString(dollarsFraction)
                );
            } else {
                priceStr = Strings.toString(dollars);
            }
        }

        formattedPrice = string.concat("$", priceStr);
    }

    function formatApr(uint apr) external pure returns (string memory formattedApr) {
        uint aprInt = apr * 100 / ConstantsLib.DENOMINATOR;
        uint aprFraction = (apr - aprInt * ConstantsLib.DENOMINATOR / 100) / 10;
        string memory delimiter = ".";
        if (aprFraction < 10) {
            delimiter = ".0";
        }
        formattedApr = string.concat(Strings.toString(aprInt), delimiter, Strings.toString(aprFraction), "%");
    }

    function implodeSymbols(
        address[] memory assets,
        string memory delimiter
    ) external view returns (string memory outString) {
        return implode(getSymbols(assets), delimiter);
    }

    function implode(string[] memory strings, string memory delimiter) public pure returns (string memory outString) {
        uint len = strings.length;
        if (len == 0) {
            return "";
        }
        outString = strings[0];
        // nosemgrep
        for (uint i = 1; i < len; ++i) {
            outString = string.concat(outString, delimiter, strings[i]);
        }
        return outString;
    }

    function getSymbols(address[] memory assets) public view returns (string[] memory symbols) {
        uint len = assets.length;
        symbols = new string[](len);
        // nosemgrep
        for (uint i; i < len; ++i) {
            symbols[i] = IERC20Metadata(assets[i]).symbol();
        }
    }

    function bytesToBytes32(bytes memory b) external pure returns (bytes32 out) {
        // nosemgrep
        for (uint i; i < b.length; ++i) {
            out |= bytes32(b[i] & 0xFF) >> (i * 8);
        }
        // return out;
    }

    function bToHex(bytes memory buffer) external pure returns (string memory) {
        // Fixed buffer size for hexadecimal convertion
        bytes memory converted = new bytes(buffer.length * 2);
        bytes memory _base = "0123456789abcdef";
        uint baseLength = _base.length;
        // nosemgrep
        for (uint i; i < buffer.length; ++i) {
            converted[i * 2] = _base[uint8(buffer[i]) / baseLength];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % baseLength];
        }
        return string(abi.encodePacked(converted));
    }

    function shortId(string memory id) external pure returns (string memory) {
        uint words = 1;
        bytes memory idBytes = bytes(id);
        uint idBytesLength = idBytes.length;
        // nosemgrep
        for (uint i; i < idBytesLength; ++i) {
            if (keccak256(bytes(abi.encodePacked(idBytes[i]))) == keccak256(bytes(" "))) {
                ++words;
            }
        }
        bytes memory _shortId = new bytes(words);
        uint k = 1;
        _shortId[0] = idBytes[0];
        // nosemgrep
        for (uint i = 1; i < idBytesLength; ++i) {
            if (keccak256(bytes(abi.encodePacked(idBytes[i]))) == keccak256(bytes(" "))) {
                if (keccak256(bytes(abi.encodePacked(idBytes[i + 1]))) == keccak256(bytes("0"))) {
                    _shortId[k] = idBytes[i + 3];
                } else {
                    _shortId[k] = idBytes[i + 1];
                }
                ++k;
            }
        }
        return string(abi.encodePacked(_shortId));
    }

    function eq(string memory a, string memory b) external pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function u2s(uint num) external pure returns (string memory) {
        return Strings.toString(num);
    }

    function i2s(int num) external pure returns (string memory) {
        return Strings.toString(num > 0 ? uint(num) : uint(-num));
    }
}
