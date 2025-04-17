// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import "../../chains/sonic/SonicLib.sol";
import "../base/UniversalTest.sol";
import {RebalanceHelper} from "../../src/periphery/RebalanceHelper.sol";
import {IUniswapV3PoolImmutables} from "../../src/integrations/uniswapv3/pool/IUniswapV3PoolImmutables.sol";
import {IUniswapV3PoolState} from "../../src/integrations/uniswapv3/pool/IUniswapV3PoolState.sol";

contract RebalanceTriggerTest is SonicSetup, UniversalTest {
    RebalanceHelper public rebalanceHelper;

    constructor() {
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.5 hours;

        makePoolVolumePriceImpactTolerance = 34_000;
        poolVolumeSwapAmount0MultiplierForPool[SonicConstantsLib.POOL_SHADOW_CL_wS_WETH] = 500; // 500k
        poolVolumeSwapAmount1MultiplierForPool[SonicConstantsLib.POOL_SHADOW_CL_wS_WETH] = 650; // 650k
        poolVolumeSwapAmount0MultiplierForPool[SonicConstantsLib.POOL_SHADOW_CL_wS_BRUSH_5000] = 800;
        poolVolumeSwapAmount1MultiplierForPool[SonicConstantsLib.POOL_SHADOW_CL_wS_BRUSH_5000] = 400;

        rebalanceHelper = new RebalanceHelper();
    }

    function testASF() public universalTest {
        _addStrategy(25); // wS_WETH 3000
        _addStrategy(26); // wS_WETH 1500
        _addStrategy(27); // wS_USDC 3000
        _addStrategy(28); // wS_USDC 1500
        _addStrategy(29);
        _addStrategy(30);
    }

    function _rebalance() internal override {
        if (IALM(currentStrategy).needRebalance()) {
            _validateNeedBalance();

            (bool[] memory burnOldPositions, IALM.NewPosition[] memory mintNewPositions) =
                rebalanceHelper.calcRebalanceArgs(currentStrategy, 10);

            IALM(currentStrategy).rebalance(burnOldPositions, mintNewPositions);

            rebalanceHelper.VERSION();
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

    function _validateNeedBalance() public view {
        IALM.Position[] memory positions = IALM(currentStrategy).positions();

        // int24 initialTick = ALMLib.getUniswapV3CurrentTick(ILPStrategy(currentStrategy).pool());
        // Check algorithm is set to ALGO_FILL_UP
        // assertEq(IALM(currentStrategy).algoId(), ALMLib.ALGO_FILL_UP, "ALM algoId is not ALGO_FILL_UP");
        uint len = positions.length;
        // Check if positions exist
        assertGt(len, 0, "ALM positions length is 0");

        int24 tickSpacing = ALMLib.getUniswapV3TickSpacing(ILPStrategy(currentStrategy).pool());
        int24 currentTick = ALMLib.getUniswapV3CurrentTick(ILPStrategy(currentStrategy).pool());
        bool rebalanceBasePosition = false;
        bool rebalanceLimitPosition = false;

        {
            // Base Position Rebalancing Logic
            (,,, int24[] memory params) = IALM(currentStrategy).preset();
            int24 halfRange = params[0] / 2;
            int24 halfTriggerRange = params[1] / 2;
            int24 oldTickLower = positions[0].tickLower;
            int24 oldTickUpper = positions[0].tickUpper;
            int24 oldMedianTick = oldTickLower + halfRange;
            bool fillUpRebalanceTrigger =
                (currentTick > oldMedianTick + halfTriggerRange) || (currentTick < oldMedianTick - halfTriggerRange);
            bool outOfRange = currentTick < oldTickLower || currentTick > oldTickUpper;

            bool cantMoveRange = false;
            if (outOfRange) {
                int24 tickDistance =
                    currentTick > oldTickUpper ? currentTick - oldTickUpper : oldTickLower - currentTick;
                tickDistance = tickDistance / tickSpacing * tickSpacing;
                if (tickDistance == 0) {
                    cantMoveRange = true;
                }
            }

            rebalanceBasePosition = !cantMoveRange && fillUpRebalanceTrigger;
        }

        // Limit Position Rebalancing Logic
        if (len > 1 && !rebalanceBasePosition) {
            int24 limitTickLower = positions[1].tickLower;
            int24 limitTickUpper = positions[1].tickUpper;
            // Check if moving the range is feasible
            int24 tickDistance;
            if (currentTick < limitTickLower) {
                tickDistance = (limitTickLower - currentTick) / tickSpacing * tickSpacing;
            } else if (currentTick > limitTickUpper) {
                tickDistance = (currentTick - limitTickUpper) / tickSpacing * tickSpacing;
            } else {
                tickDistance = 0; // No movement needed
            }

            assertNotEq(tickDistance, 0, "Moving the range is not feasible");

            // If tickDistance is zero, moving the range is not feasible
            if (tickDistance != 0) {
                rebalanceLimitPosition = true;
            }
        }
        if (rebalanceBasePosition) console.log("rebalanceBasePosition is True");
        if (rebalanceLimitPosition) console.log("rebalanceLimitPosition is True");

        assertTrue(rebalanceBasePosition || rebalanceLimitPosition, "ALM strategy does not need to rebalance");
    }

    function testNeedRebalance_LimitPositionBranches() public universalTest {
        // 1. Get Storage pointers
        IALM.ALMStrategyBaseStorage storage almStrategy;
        ILPStrategy.LPStrategyBaseStorage storage lpStrategy;
        IStrategy.StrategyBaseStorage storage strategyBase;

        //Get $ for ALMStrategyBase
        bytes32 alm_strategy_location = 0xa7b5cf2e827fe3bcf3fe6a0f3315b77285780eac3248f46a43fc1c44c1d47900;
        assembly {
            almStrategy.slot := alm_strategy_location
        }

        //Get $_$ for LPStrategyBase
        bytes32 lp_strategy_location = 0x72189c387e876b9a88f41e18ce5929a30f87f78bd01fd02027d49c1ff673554f;
        assembly {
            lpStrategy.slot := lp_strategy_location
        }

        //Get __$__ for StrategyBase
        bytes32 strategy_location = 0x534261688bdf3f7c39c3a02e62205067b50727e2b3f4438fbc6918965fa85d82;
        assembly {
            strategyBase.slot := strategy_location
        }

        // Set algoId and params
        almStrategy.algoId = ALMLib.ALGO_FILL_UP;
        almStrategy.params = new int24[](2);
        almStrategy.params[0] = 1000;
        almStrategy.params[1] = 200;

        // Add two positions
        almStrategy.positions.push();
        almStrategy.positions[0].tickLower = -500;
        almStrategy.positions[0].tickUpper = 500;
        almStrategy.positions.push();
        almStrategy.positions[1].tickLower = 1000;
        almStrategy.positions[1].tickUpper = 2000;

        // Mock tickSpacing
        address pool = lpStrategy.pool;
        int24 tickSpacing = 10;
        vm.mockCall(
            pool, abi.encodeWithSelector(IUniswapV3PoolImmutables.tickSpacing.selector), abi.encode(tickSpacing)
        );

        // --------- Case 1: currentTick < limitTickLower (tickDistance != 0, should return true) ---------
        int24 currentTick1 = 900; // less than 1000
        vm.mockCall(
            pool,
            abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
            abi.encode(uint160(0), currentTick1, uint16(0), uint16(0), uint16(0), uint8(0), bool(false))
        );
        bool need1 = ALMLib.needRebalance(almStrategy, lpStrategy);
        assertTrue(need1, "Should need rebalance when currentTick < limitTickLower");

        // --------- Case 2: currentTick > limitTickUpper (tickDistance != 0, should return true) ---------
        int24 currentTick2 = 2100; // greater than 2000
        vm.mockCall(
            pool,
            abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
            abi.encode(uint160(0), currentTick2, uint16(0), uint16(0), uint16(0), uint8(0), bool(false))
        );
        bool need2 = ALMLib.needRebalance(almStrategy, lpStrategy);
        assertTrue(need2, "Should need rebalance when currentTick > limitTickUpper");

        // --------- Case 3: currentTick inside limit position (tickDistance == 0, should return false) ---------
        // int24 currentTick3 = 1500; // between 1000 and 2000
        // vm.mockCall(
        //     pool,
        //     abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
        //     abi.encode(uint160(0), currentTick3, uint16(0), uint16(0), uint16(0), uint8(0), bool(false))
        // );
        // bool need3 = ALMLib.needRebalance(almStrategy, lpStrategy);
        // assertFalse(need3, "Should NOT need rebalance when currentTick inside limit position");
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
