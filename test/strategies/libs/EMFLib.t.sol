// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EMFLib} from "../../../src/strategies/libs/EMFLib.sol";

contract EMFLibUnitTests is Test {
    function setUp() public {
        // Set up any necessary state or variables here
    }

    function testRemoveTokenFromListTokenNotPresent() public pure {
        address token = address(0x1);

        address[] memory assets = new address[](3);
        assets[0] = address(0x2);
        assets[1] = address(0x3);
        assets[2] = address(0x4);

        uint[] memory amounts = new uint[](3);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;

        (address[] memory newAssets, uint[] memory newAmounts) = EMFLib.removeTokenFromList(token, assets, amounts);

        assertEq(newAssets.length, assets.length);
        assertEq(newAmounts.length, amounts.length);

        for (uint i = 0; i < assets.length; i++) {
            assertEq(newAssets[i], assets[i]);
            assertEq(newAmounts[i], amounts[i]);
        }
    }

    function testRemoveTokenFromListSingleTokenEntry() public pure {
        address token = address(0x1);

        address[] memory assets = new address[](3);
        assets[0] = address(0x2);
        assets[1] = address(0x1); // Token to be removed
        assets[2] = address(0x4);

        uint[] memory amounts = new uint[](3);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;

        (address[] memory newAssets, uint[] memory newAmounts) = EMFLib.removeTokenFromList(token, assets, amounts);

        assertEq(newAssets.length, assets.length - 1);
        assertEq(newAmounts.length, amounts.length - 1);
        assertEq(newAssets[0], assets[0]);
        assertEq(newAssets[1], assets[2]);
        assertEq(newAmounts[0], amounts[0]);
        assertEq(newAmounts[1], amounts[2]);
    }

    function testRemoveTokenFromListShouldRemoveAllTokens() public pure {
        address token = address(0x1);

        address[] memory assets = new address[](3);
        assets[0] = address(0x1);
        assets[1] = address(0x1); // Token to be removed
        assets[2] = address(0x1);

        uint[] memory amounts = new uint[](3);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;

        (address[] memory newAssets, uint[] memory newAmounts) = EMFLib.removeTokenFromList(token, assets, amounts);

        assertEq(newAssets.length, 0);
        assertEq(newAmounts.length, 0);
    }
}
