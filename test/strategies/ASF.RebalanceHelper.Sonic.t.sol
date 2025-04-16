// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import "../../chains/sonic/SonicLib.sol";
import "../base/UniversalTest.sol";
import {RebalanceHelper} from "../../src/periphery/RebalanceHelper.sol";
import {IALM} from "../../src/interfaces/IALM.sol";
import {ILPStrategy} from "../../src/interfaces/ILPStrategy.sol";
import {ALMLib} from "../../src/strategies/libs/ALMLib.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract ALMShadowFarmStrategyTest is SonicSetup, UniversalTest {
    RebalanceHelper public rebalanceHelper;

    struct CalcRebalanceVars {
        uint algoId;
        int24[] params;
        address pool;
        bool baseRebalanceNeeded;
        bool limitRebalanceNeeded;
        int24 currentTick;
        int24 tickSpacing;
        uint[] amounts;
        uint addedLiquidity;
        uint[] amountsConsumed;
        int24 lowerTickLower;
        int24 lowerTickUpper;
        int24 upperTickLower;
        int24 upperTickUpper;
        int24[] fillUpTicksLowerSide;
        int24[] fillUpTicksUpperSide;
        uint fillUpLiquidityLowerSide;
        uint fillUpLiquidityUpperSide;
        uint[] fillUpAmountsConsumedLowerSide;
        uint[] fillUpAmountsConsumedUpperSide;
    }

    constructor() {
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.5 hours;

        makePoolVolumePriceImpactTolerance = 34_000;
        poolVolumeSwapAmount0MultiplierForPool[SonicConstantsLib.POOL_SHADOW_CL_wS_WETH] = 100;
        poolVolumeSwapAmount1MultiplierForPool[SonicConstantsLib.POOL_SHADOW_CL_wS_WETH] = 150;
        poolVolumeSwapAmount0MultiplierForPool[SonicConstantsLib.POOL_SHADOW_CL_wS_BRUSH_5000] = 80;
        poolVolumeSwapAmount1MultiplierForPool[SonicConstantsLib.POOL_SHADOW_CL_wS_BRUSH_5000] = 40;

        rebalanceHelper = new RebalanceHelper();
    }

    function testASF() public universalTest {
        _addStrategy(25); // wS_WETH 3000
        _addStrategy(26); // wS_WETH 1500
        _addStrategy(27); // wS_USDC 3000
        _addStrategy(28); // wS_USDC 1500
        _addStrategy(29); // SACRA-scUSD 120000
        _addStrategy(30); // SACRA-scUSD 800
    }

    function _rebalance() internal override {
        // Check if rebalance is needed
        if (!IALM(currentStrategy).needRebalance()) {
            vm.expectRevert(IALM.NotNeedRebalance.selector);
            rebalanceHelper.calcRebalanceArgs(currentStrategy, 10);
        }
        if (IALM(currentStrategy).needRebalance()) {
            // Initialize variables using CalcRebalanceVars struct
            CalcRebalanceVars memory v;

            // Retrieve strategy preset and positions
            (v.algoId,,, v.params) = IALM(currentStrategy).preset();

            v.pool = ILPStrategy(currentStrategy).pool();
            v.tickSpacing = ALMLib.getUniswapV3TickSpacing(v.pool);
            v.currentTick = ALMLib.getUniswapV3CurrentTick(v.pool);
            // ICAmmAdapter adapter = ICAmmAdapter(address(ILPStrategy(currentStrategy).ammAdapter()));
            // slither-disable-next-line unused-return
            (, v.amounts) = IStrategy(currentStrategy).assetsAmounts();

            // Store initial state
            IALM.Position[] memory initialPositions = IALM(currentStrategy).positions();
            int24 initialTick = ALMLib.getUniswapV3CurrentTick(ILPStrategy(currentStrategy).pool());

            console.log("here");
            // Execute rebalance
            (bool[] memory burnOldPositions, IALM.NewPosition[] memory mintNewPositions) =
                rebalanceHelper.calcRebalanceArgs(currentStrategy, 10);
            console.log("here");

            IALM(currentStrategy).rebalance(burnOldPositions, mintNewPositions);

            // Post-rebalance validation
            _validateNewPositions(mintNewPositions, initialTick, initialPositions, burnOldPositions);
        }
    }

    function _validateBurnFlags(bool[] memory burnFlags, uint initialCount) internal pure {
        require(burnFlags.length == initialCount, "Incorrect burn flags length");
        for (uint i = 0; i < burnFlags.length; i++) {
            require(burnFlags[i], "All positions should be marked for burn");
            assertTrue(burnFlags[i], string(abi.encodePacked("burnOldPositions[", vm.toString(i), "] should be true")));
        }
    }

    function _validateNewPositions(
        IALM.NewPosition[] memory newPositions,
        int24 currentTick,
        IALM.Position[] memory oldPositions,
        bool[] memory burnOldPositions
    ) internal {
        require(newPositions.length == 1 || newPositions.length == 2, "Invalid new positions count");

        // Validate base position
        _validatePosition(newPositions[0], currentTick, oldPositions, burnOldPositions);

        // Validate fill-up position if exists
        if (newPositions.length > 1) {
            _validateFillUpPosition(newPositions[1], currentTick);
        }
    }

    function _validatePosition(
        IALM.NewPosition memory position,
        int24 currentTick,
        IALM.Position[] memory oldPositions,
        bool[] memory burnOldPositions
    ) internal {
        // Tick validation
        int24 tickSpacing = ALMLib.getUniswapV3TickSpacing(ILPStrategy(currentStrategy).pool());
        require((position.tickUpper - position.tickLower) % tickSpacing == 0, "Invalid tick spacing");
        require(position.tickLower < position.tickUpper, "Invalid tick range");

        uint positionsLength = oldPositions.length;

        // Check if base position needs rebalancing
        bool baseRebalanceNeeded = currentTick < oldPositions[0].tickLower || currentTick > oldPositions[0].tickUpper;

        if (baseRebalanceNeeded) {
            // Validate burn flags
            for (uint i = 0; i < positionsLength; i++) {
                require(burnOldPositions[i], "All positions should be marked for burn");
                assertTrue(
                    burnOldPositions[i],
                    string(abi.encodePacked("burnOldPositions[", vm.toString(i), "] should be true"))
                );
            }

            // Verify position shift
            int24 expectedShift = _calculateExpectedShift(currentTick, oldPositions[0], tickSpacing);
            if (expectedShift == 0) {
                vm.expectRevert(IALM.CantDoRebalance.selector);
            }
            // Validate position ticks
            require(
                position.tickLower == oldPositions[0].tickLower + expectedShift
                    && position.tickUpper == oldPositions[0].tickUpper + expectedShift,
                "Incorrect position shift"
            );
        } else {
            // Verify base position ticks
            (,,, int24[] memory params) = IALM(currentStrategy).preset();
            (int24 expectedLower, int24 expectedUpper) = ALMLib.calcFillUpBaseTicks(currentTick, params[0], tickSpacing);
            require(
                position.tickLower == expectedLower && position.tickUpper == expectedUpper,
                "Incorrect base position ticks"
            );
        }

        // Liquidity validation
        require(position.liquidity > 0, "Position liquidity must be positive");
        require(position.minAmount0 > 0 && position.minAmount1 > 0, "Invalid slippage protection");
    }

    function _validateFillUpPosition(IALM.NewPosition memory fillUp, int24 currentTick) internal view {
        int24 tickSpacing = ALMLib.getUniswapV3TickSpacing(ILPStrategy(currentStrategy).pool());
        // Calculate expected fill-up ranges based on current tick
        int24 expectedLowerLower = currentTick > 0
            ? (currentTick / tickSpacing * tickSpacing)
            : (currentTick / tickSpacing * tickSpacing - tickSpacing);

        int24 expectedLowerUpper = expectedLowerLower + tickSpacing;
        int24 expectedUpperLower = expectedLowerUpper;
        int24 expectedUpperUpper = expectedUpperLower + tickSpacing;

        bool isValidLowerFillUp = fillUp.tickLower == expectedLowerLower && fillUp.tickUpper == expectedLowerUpper;

        bool isValidUpperFillUp = fillUp.tickLower == expectedUpperLower && fillUp.tickUpper == expectedUpperUpper;

        require(isValidLowerFillUp || isValidUpperFillUp, "Fill-up position not adjacent to current price range");
    }

    function _calculateExpectedShift(
        int24 currentTick,
        IALM.Position memory oldPosition,
        int24 tickSpacing
    ) internal pure returns (int24) {
        if (currentTick > oldPosition.tickUpper) {
            return ((currentTick - oldPosition.tickUpper) / tickSpacing) * tickSpacing;
        } else {
            return -((oldPosition.tickLower - currentTick) / tickSpacing) * tickSpacing;
        }
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.ALM_SHADOW_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }

    // // Additional test cases
    function testNonALMStrategy() public universalTest {
        // Mock a contract that does not implement the IALM interface
        address nonALMStrategy = address(new MockNonALMStrategy());

        // Expect the call to revert with NotALM error
        vm.expectRevert(IALM.NotALM.selector);
        rebalanceHelper.calcRebalanceArgs(nonALMStrategy, 10);
    }
}

// Mock contract that does not implement the IALM interface
contract MockNonALMStrategy is IERC165 {
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId; // Only supports IERC165, not IALM
    }
}
