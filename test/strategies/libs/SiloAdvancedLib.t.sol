// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console, Test} from "forge-std/Test.sol";
import {SiloAdvancedLib} from "../../../src/strategies/libs/SiloAdvancedLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract SiloAdvancedLibUnitTests is Test {
    function setUp() public {
        // Set up any necessary state or variables here
    }

    function testCalculateNewLeverageSquareEq() public pure {
        uint totalCollateralUsd = 1_711_884e6;
        uint ltv = 8712;
        uint borrowAssetUsd = totalCollateralUsd * ltv / 10_000;
        uint priceImpactTolerance = 1000;
        uint xUsd = 2_000e6;

        uint leverageNew =
            SiloAdvancedLib._calculateNewLeverage(totalCollateralUsd, borrowAssetUsd, priceImpactTolerance, xUsd);

        assertApproxEqAbs(leverageNew, 79032, 1);
    }

    function testCalculateNewLeverageLinearEq() public pure {
        uint totalCollateralUsd = 1_711_884e6;
        uint ltv = 8712;
        uint borrowAssetUsd = totalCollateralUsd * ltv / 10_000;
        uint priceImpactTolerance = 0;
        uint xUsd = 2_000e6;

        uint leverageNew =
            SiloAdvancedLib._calculateNewLeverage(totalCollateralUsd, borrowAssetUsd, priceImpactTolerance, xUsd);

        assertApproxEqAbs(leverageNew, 78982, 1);
    }

    function testCalculateNewLeverageLinearEqZeroLeverage() public pure {
        uint totalCollateralUsd = 1_711_884e6;
        uint ltv = 8712;
        uint borrowAssetUsd = totalCollateralUsd * ltv / 10_000;
        uint priceImpactTolerance = 0;
        uint xUsd = totalCollateralUsd + 1;

        uint leverageNew =
            SiloAdvancedLib._calculateNewLeverage(totalCollateralUsd, borrowAssetUsd, priceImpactTolerance, xUsd);

        assertApproxEqAbs(leverageNew, 0, 1);
    }
}
