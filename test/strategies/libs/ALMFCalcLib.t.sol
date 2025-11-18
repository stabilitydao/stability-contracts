// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ALMFCalcLib} from "../../../src/strategies/libs/ALMFCalcLib.sol";
import {Test} from "forge-std/Test.sol";

contract ALMFCalcLibTest is Test {
    uint internal constant FORK_BLOCK = 55065335; // Nov-13-2025 03:53:58 AM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
    }

    function testSplitDepositAmount() public pure {
        (uint aD, uint aR) = ALMFCalcLib.splitDepositAmount(400, 20000, 1000, 550, 0.015e18);
        assertEq(aD, 400, "1.ad");
        assertEq(aR, 0, "1.ar");

        (aD, aR) = ALMFCalcLib.splitDepositAmount(400e2, 20000, 1000e2, 800e2, 0.015e18);
        assertEq(aD, 193.82e2, "2.ad");
        assertEq(aR, 206.18e2, "2.ar");

        (aD, aR) = ALMFCalcLib.splitDepositAmount(400e2, 20000, 1000e2, 900e2, 0.015e18);
        assertEq(aD, 0, "3.ad");
        assertEq(aR, 400e2, "3.ar");

        (aD, aR) = ALMFCalcLib.splitDepositAmount(400e18, 20000, 1000e18, 810e18, 0);
        assertEq(aD, 180e18, "4.ad");
        assertEq(aR, 220e18, "4.ar");
    }

    function testCalcWithdrawAmountsUnitPrices() public pure {
        ALMFCalcLib.StaticData memory data;
        data.decimalsC = 18;
        data.decimalsB = 6;
        data.priceC18 = 1e18;
        data.priceB18 = 1e18;

        (uint flashAmount, uint collateralToWithdraw) =
            ALMFCalcLib.calcWithdrawAmounts(200e18, 32700, data, state(1000e18, 700e18));
        assertApproxEqRel(flashAmount, 473.33e6, 1e18 / 100, "1.F");
        assertApproxEqRel(collateralToWithdraw, 673.33e18, 1e18 / 100, "1.C1");

        (flashAmount, collateralToWithdraw) =
            ALMFCalcLib.calcWithdrawAmounts(200e18, 14571, data, state(1000e18, 300e18));
        assertApproxEqRel(flashAmount, 71.43e6, 1e18 / 100, "2.F");
        assertApproxEqRel(collateralToWithdraw, 271.43e18, 1e18 / 100, "2.C1");

        (flashAmount, collateralToWithdraw) =
            ALMFCalcLib.calcWithdrawAmounts(0.0001e18, 14571, data, state(1000e18, 300e18));
        assertEq(flashAmount, 0, "3.F");
        assertEq(collateralToWithdraw, 0.0001e18, "3.C1");

        (flashAmount, collateralToWithdraw) =
            ALMFCalcLib.calcWithdrawAmounts(700e18, 14571, data, state(1000e18, 300e18));
        assertApproxEqRel(flashAmount, 300.0e6, 1e18 / 100, "4.F");
        assertApproxEqRel(collateralToWithdraw, 1000e18, 1e18 / 100, "4.C1");

        (flashAmount, collateralToWithdraw) =
            ALMFCalcLib.calcWithdrawAmounts(99.99e18, 96000, data, state(1000e18, 900e18));
        assertApproxEqRel(flashAmount, 899.91e6, 1e18 / 100, "5.F");
        assertApproxEqRel(collateralToWithdraw, 999.9e18, 1e18 / 100, "5.C1");

        // ----------------- special case: negative F
        (flashAmount, collateralToWithdraw) =
            ALMFCalcLib.calcWithdrawAmounts(100e18, 19400, data, state(1000e18, 200e18));
        assertEq(flashAmount, 0, "6.F");
        assertEq(collateralToWithdraw, 100e18, "6.C1");
    }

    function testGetLimitedAmount() public pure {
        // optionalLimit == 0 -> returns full amount
        assertEq(ALMFCalcLib.getLimitedAmount(100, 0), 100, "limit0 returns amount");

        // optionalLimit greater than amount -> returns amount
        assertEq(ALMFCalcLib.getLimitedAmount(100, 200), 100, "limit>amount returns amount");

        // optionalLimit less than amount -> returns optionalLimit
        assertEq(ALMFCalcLib.getLimitedAmount(100, 50), 50, "limit<amount returns limit");

        // edge cases
        assertEq(ALMFCalcLib.getLimitedAmount(0, 0), 0, "zero amount and zero limit");
        assertEq(ALMFCalcLib.getLimitedAmount(0, 10), 0, "zero amount with positive limit");

        // large numbers
        uint large = 1e30;
        assertEq(ALMFCalcLib.getLimitedAmount(large, 0), large, "large amount with zero limit");
        assertEq(ALMFCalcLib.getLimitedAmount(large, large - 1), large - 1, "large limit smaller than amount");
    }

    function testStateCalculations() public pure {
        // getLeverage
        // collateral 1000, debt 500 -> leverage = 1000*10000/(1000-500) = 20000
        assertEq(ALMFCalcLib.getLeverage(1000, 500), 20000, "getLeverage basic");
        // zero collateral -> 0
        assertEq(ALMFCalcLib.getLeverage(0, 0), 0, "getLeverage zero collateral");
        // collateral 1000, debt 800 -> 1000*10000/(200) = 50000
        assertEq(ALMFCalcLib.getLeverage(1000, 800), 50000, "getLeverage high debt");

        // getLtv
        // collateral 1000, debt 500 -> ltv = 500*10000/1000 = 5000
        assertEq(ALMFCalcLib.getLtv(1000, 500), 5000, "getLtv basic");
        // zero collateral -> 0
        assertEq(ALMFCalcLib.getLtv(0, 100), 0, "getLtv zero collateral");

        // leverageToLtv
        // leverage 20000 -> ltv = 10000 - 10000*10000/20000 = 5000
        assertEq(ALMFCalcLib.leverageToLtv(20000), 5000, "leverageToLtv basic");
        // leverage equal to INTERNAL_PRECISION (10000) -> 0
        assertEq(ALMFCalcLib.leverageToLtv(10000), 0, "leverageToLtv <= INTERNAL_PRECISION");

        // ltvToLeverage
        // ltv 5000 -> leverage = 10000*10000/(10000-5000) = 20000
        assertEq(ALMFCalcLib.ltvToLeverage(5000), 20000, "ltvToLeverage basic");
    }

    function testBaseConversions() public pure {
        ALMFCalcLib.StaticData memory data;

        // collateralToBase / baseToCollateral with decimalsC = 6 and priceC18 = 2e18
        data.decimalsC = 6;
        data.priceC18 = 2e18;

        // 1 token (1e6 with 6 decimals) -> base = 1e6 * 2e18 / 1e6 = 2e18
        assertEq(ALMFCalcLib.collateralToBase(1e6, data), 2e18, "collateralToBase basic");
        // inverse: base 2e18 -> token = 2e18 * 1e6 / 2e18 = 1e6
        assertEq(ALMFCalcLib.baseToCollateral(2e18, data), 1e6, "baseToCollateral basic");

        // borrowToBase / baseToBorrow with decimalsB = 8 and priceB18 = 5e18
        data.decimalsB = 8;
        data.priceB18 = 5e18;

        // 3 tokens (3e8 with 8 decimals) -> base = 3e8 * 5e18 / 1e8 = 15e18
        assertEq(ALMFCalcLib.borrowToBase(3e8, data), 15e18, "borrowToBase basic");
        // inverse: base 15e18 -> token = 15e18 * 1e8 / 5e18 = 3e8
        assertEq(ALMFCalcLib.baseToBorrow(15e18, data), 3e8, "baseToBorrow basic");

        // edge cases: zero
        data.decimalsC = 18;
        data.priceC18 = 1e18;
        assertEq(ALMFCalcLib.collateralToBase(0, data), 0, "collateralToBase zero");
        assertEq(ALMFCalcLib.baseToCollateral(0, data), 0, "baseToCollateral zero");
    }

    function testCollateralBaseRounding() public pure {
        ALMFCalcLib.StaticData memory data;

        // Case A: decimalsC = 6, price slightly above 1e18 to force rounding loss for tiny amounts
        data.decimalsC = 6;
        data.priceC18 = 1e18 + 1;

        // smallest unit amount = 1 -> base = floor((1 * (1e18+1)) / 1e6) = 1e12
        uint base1 = ALMFCalcLib.collateralToBase(1, data);
        assertEq(base1, 1e12, "base1 expected");

        // converting back loses precision: floor((1e12 * 1e6) / (1e18+1)) = 0
        uint recovered1 = ALMFCalcLib.baseToCollateral(base1, data);
        assertEq(recovered1, 0, "recovered1 expected 0 due to rounding");

        // Case B: full token equal to 1e6 (with decimals 6) should be invertible
        uint amountToken = 1e6; // 1.0 token in 6 decimals
        uint base2 = ALMFCalcLib.collateralToBase(amountToken, data);
        assertEq(base2, 1e18 + 1, "base2 expected exact price * amount");

        uint recovered2 = ALMFCalcLib.baseToCollateral(base2, data);
        assertEq(recovered2, amountToken, "recovered2 should equal original amountToken");

        // sanity property: recovered <= original for any amount (rounding down)
        uint someAmount = 999999;
        uint b = ALMFCalcLib.collateralToBase(someAmount, data);
        uint r = ALMFCalcLib.baseToCollateral(b, data);
        assertTrue(r <= someAmount, "round-trip recovered <= original");
    }

    //region -------------------------------------- Internal logic
    function state(uint collateralBase, uint debtBase) internal pure returns (ALMFCalcLib.State memory) {
        ALMFCalcLib.State memory _state;
        _state.collateralBase = collateralBase;
        _state.debtBase = debtBase;
        return _state;
    }

    //endregion -------------------------------------- Internal logic
}
