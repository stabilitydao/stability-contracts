// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {LibString} from "@solady/utils/LibString.sol";
import {Base64 as SoladyBase64} from "@solady/utils/Base64.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";

abstract contract Utils is Test {
    using LibString for string;

    /// @dev Extracts the SVG from a base-64 encoded token URI.
    function parseURI(string memory uri)
        public
        pure
        returns (string memory name, string memory description, string memory svg)
    {
        string memory uriBase64 = uri.replace({search: "data:application/json;base64,", replacement: ""});
        string memory decodedURI = string(SoladyBase64.decode(uriBase64));
        name = vm.parseJsonString(decodedURI, ".name");
        description = vm.parseJsonString(decodedURI, ".description");
        string memory image = vm.parseJsonString(decodedURI, ".image");
        string memory sanitizedImage = image.replace({search: "data:image/svg+xml;base64,", replacement: ""});
        svg = string(SoladyBase64.decode(sanitizedImage));
    }

    function writeNftSvgToFile(
        address nft_,
        uint tokenId,
        string memory path
    ) public returns (string memory name, string memory description, string memory svg) {
        IERC721Metadata nft = IERC721Metadata(nft_);
        string memory tokenUri = nft.tokenURI(tokenId);
        assertGt(bytes(tokenUri).length, 0);
        (name, description, svg) = parseURI(tokenUri);
        vm.writeFile(path, svg);
        assertEq(vm.readFile(path), svg);
    }

    function _formatSharePrice(uint price) internal pure returns (string memory) {
        uint intPrice = price / 1e18;
        uint decimalPrice = price - intPrice * 1e18;
        return string.concat(CommonLib.u2s(intPrice), ".", CommonLib.u2s(decimalPrice));
    }

    function _formatLtv(uint ltv) internal pure returns (string memory) {
        uint intAmount = ltv / 100;
        uint decimalAmount = ltv - intAmount * 100;
        return string.concat(CommonLib.u2s(intAmount), ".", CommonLib.u2s(decimalAmount), "%");
    }

    function _formatLeverage(uint amount) internal pure returns (string memory) {
        uint intAmount = amount / 100_00;
        uint decimalAmount = amount - intAmount * 100_00;
        return string.concat("x", CommonLib.u2s(intAmount), ".", CommonLib.u2s(decimalAmount));
    }

    function testUtils() external {}
}
