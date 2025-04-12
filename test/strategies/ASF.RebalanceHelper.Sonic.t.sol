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

// Mock contract that does not implement the IALM interface
contract MockNonALMStrategy is IERC165 {
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

contract ALMShadowFarmStrategyTest is SonicSetup, UniversalTest {
    RebalanceHelper public rebalanceHelper;

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
        if (!isALMStrategy(currentStrategy)) return;
        if (IALM(currentStrategy).needRebalance()) {
            (bool[] memory burnOldPositions, IALM.NewPosition[] memory mintNewPositions) =
                rebalanceHelper.calcRebalanceArgs(currentStrategy, 10);

            _validateRebalance(mintNewPositions, burnOldPositions);

            IALM(currentStrategy).rebalance(burnOldPositions, mintNewPositions);
        }
    }

    function _validateRebalance(IALM.NewPosition[] memory newPositions, bool[] memory burnOldPositions) internal view {
        // Basic sanity checks after rebalance
        IALM.Position[] memory positions = IALM(currentStrategy).positions();
        require(positions.length > 0, "No positions after rebalance");

        //Tick spacing
        int24 tickSpacing = ALMLib.getUniswapV3TickSpacing(ILPStrategy(currentStrategy).pool());

        //Base position
        require(newPositions.length > 0, "No new base positions found");
        require(
            (newPositions[0].tickUpper - newPositions[0].tickLower) % tickSpacing == 0,
            "Base position tick spacing invalid"
        );

        //Fill up position
        if (newPositions.length > 1) {
            require(
                (newPositions[1].tickUpper - newPositions[1].tickLower) % tickSpacing == 0,
                "Fill up position tick spacing invalid"
            );
        }

        // Validate burn flags length matches positions length
        IALM.Position[] memory oldPositions = IALM(currentStrategy).positions();
        assertEq(burnOldPositions.length, oldPositions.length, "Burn flags length mismatch");
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

    // Add tests to increase coverage
    // function testRebalanceNotNeeded() public universalTest {
    //     // Skip if not an ALM strategy
    //     console.log("currentStrategy",currentStrategy);
    //     console.log("testRebalanceNotNeeded");
    //     if (!isALMStrategy(currentStrategy)) return;
    //     console.log("isALMStrategy passed");

    //     // Mock needRebalance to return false
    //     vm.mockCall(currentStrategy, abi.encodeWithSelector(IALM.needRebalance.selector), abi.encode(false));
    //     console.log("currentStrategy");
    //     vm.expectRevert(IALM.NotNeedRebalance.selector);
    //     console.log("NotNeedRebalance");
    //     rebalanceHelper.calcRebalanceArgs(currentStrategy, 10);
    //     console.log("calcRebalanceArgs");
    // }

    // function testNotALMStrategy() public universalTest {
    //     address nonALMStrategy = address(new MockNonALMStrategy());

    //     // Expect RebalanceHelper to revert with NotALM error when trying to calculate rebalance args
    //     vm.expectRevert(IALM.NotALM.selector);
    //     rebalanceHelper.calcRebalanceArgs(nonALMStrategy, 10);
    // }

    // function testBaseRebalanceNeeded() public universalTest {
    //     // Skip if not an ALM strategy
    //     // if (!isALMStrategy(currentStrategy)) return;

    //     // Mock the current tick to be outside the range of oldBasePosition
    //     IALM.Position[] memory positions = IALM(currentStrategy).positions();
    //     require(positions.length > 0, "No positions to test");

    //     // Get old base position range
    //     int24 oldTickLower = positions[0].tickLower;
    //     int24 oldTickUpper = positions[0].tickUpper;

    //     // Current tick out of range
    //     int24 currentTick = oldTickUpper + 10000;
    //     vm.mockCall(ILPStrategy(currentStrategy).pool(), abi.encodeWithSelector(ALMLib.getUniswapV3CurrentTick.selector), abi.encode(currentTick));

    //     (bool[] memory burnOldPositions, IALM.NewPosition[] memory mintNewPositions) = rebalanceHelper.calcRebalanceArgs(currentStrategy, 10);

    //     // Expect all positions to be burned and mint 1 new position
    //     for (uint i = 0; i < burnOldPositions.length; i++) {
    //         assertTrue(burnOldPositions[i], "All positions should be burned");
    //     }
    //     assertEq(mintNewPositions.length, 1, "Should mint 1 new position");
    // }

    // function testBaseNotRebalanceNeeded() public universalTest {
    //     // Skip if not an ALM strategy
    //     // if (!isALMStrategy(currentStrategy)) return;

    //     // Mock the current tick to be within the range of oldBasePosition
    //     IALM.Position[] memory positions = IALM(currentStrategy).positions();
    //     require(positions.length > 0, "No positions to test");

    //     // Get old base position range
    //     int24 oldTickLower = positions[0].tickLower;
    //     int24 oldTickUpper = positions[0].tickUpper;

    //     // Current tick inside range
    //     int24 currentTick = (oldTickLower + oldTickUpper) / 2;
    //     vm.mockCall(ILPStrategy(currentStrategy).pool(), abi.encodeWithSelector(ALMLib.getUniswapV3CurrentTick.selector), abi.encode(currentTick));

    //     (bool[] memory burnOldPositions, IALM.NewPosition[] memory mintNewPositions) = rebalanceHelper.calcRebalanceArgs(currentStrategy, 10);

    //     // Expect positions to be burned and mint 2 new positions
    //     for (uint i = 0; i < burnOldPositions.length; i++) {
    //         assertTrue(burnOldPositions[i], "All positions should be burned");
    //     }
    //     assertEq(mintNewPositions.length, 2, "Should mint 2 new positions");
    // }

    function isALMStrategy(address strategy) internal view returns (bool) {
        return IERC165(strategy).supportsInterface(type(IALM).interfaceId);
    }
}
