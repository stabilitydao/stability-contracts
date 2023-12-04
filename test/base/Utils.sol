// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import "@solady/utils/LibString.sol";
import {Base64 as SoladyBase64} from "@solady/utils/Base64.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

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

    function testUtils() external {}
}
