// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SiloLib} from "../../../src/strategies/libs/SiloLib.sol";

contract SiloLibUnitTests is Test {
    function setUp() public {
        // Set up any necessary state or variables here
    }

    function testCalculateNewLeverageSet1() public pure {
        SiloLib.LeverageCalcParams memory config = SiloLib.LeverageCalcParams({
            xWithdrawAmount: 100e6,
            currentCollateralAmount: 72_000e6,
            currentDebtAmount: 50_400e6,
            initialBalanceC: 0,
            alphaScaled: 0,
            betaRateScaled: 0
        });

        uint ltv = 1e18 * config.currentDebtAmount / config.currentCollateralAmount;
        uint maxLtv = 98e16;

        uint leverageNew = SiloLib.calculateNewLeverage(config, ltv, maxLtv);

        assertApproxEqAbs(leverageNew, 33979, 1);
    }

    function testCalculateNewLeverageSet2() public pure {
        SiloLib.LeverageCalcParams memory config = SiloLib.LeverageCalcParams({
            xWithdrawAmount: 1000e6,
            currentCollateralAmount: 720_000e6,
            currentDebtAmount: 576_000e6,
            initialBalanceC: 500e6,
            alphaScaled: 1e18 * (100 - 0.2) / 100,
            betaRateScaled: 1e14 //0.01%
        });

        uint leverage = 5;
        uint maxLeverage = 20;

        uint ltv = 1e18 - 1e18 / leverage; // 1e18 * config.currentDebtAmount / config.currentCollateralAmount;
        uint maxLtv = 1e18 - 1e18 / maxLeverage; // 98e16;

        uint leverageNew = SiloLib.calculateNewLeverage(config, ltv, maxLtv);

        assertApproxEqAbs(leverageNew, 50495, 1);
    }

    function testCalculateNewLeverageSet3() public pure {
        SiloLib.LeverageCalcParams memory config = SiloLib.LeverageCalcParams({
            xWithdrawAmount: 5000e6,
            currentCollateralAmount: 70_000e6,
            currentDebtAmount: 59_500e6,
            initialBalanceC: 4999e6,
            alphaScaled: 1e18 * (100 - 0.2) / 100,
            betaRateScaled: 1e15 //0.1%
        });

        //    uint leverage = 5;
        //    uint maxLeverage = 20;
        //
        //    uint ltv = 1e18 - 1e18/leverage; // 1e18 * config.currentDebtAmount / config.currentCollateralAmount;
        //    uint maxLtv = 1e18 - 1e18/maxLeverage; // 98e16;

        uint ltv = 1e18 * config.currentDebtAmount / config.currentCollateralAmount;
        uint maxLtv = 99e16;

        uint leverageNew = SiloLib.calculateNewLeverage(config, ltv, maxLtv);

        assertApproxEqAbs(leverageNew, 131664, 100);
    }
}
