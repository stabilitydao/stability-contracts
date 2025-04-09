// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {ILPStrategy} from "../../src/interfaces/ILPStrategy.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IALM} from "../../src/interfaces/IALM.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ICAmmAdapter} from "../../src/interfaces/ICAmmAdapter.sol";
import {ALMLib} from "../../src/strategies/libs/ALMLib.sol";
import {RebalanceHelper} from "../../src/periphery/RebalanceHelper.sol";

contract RebalanceHelperTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STRATEGY = 0xC37F16E3E5576496d06e3Bb2905f73574d59EAF7;
    address public vault;
    address public multisig;
    address public pool;
    ICAmmAdapter public ammAdapter;

    RebalanceHelper public rebalanceHelper;

    function setUp() public {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"), 6288137); // Feb-02-2025 08:08:16 PM +UTC

        vault = IStrategy(STRATEGY).vault();
        multisig = IPlatform(IControllable(STRATEGY).platform()).multisig();
        pool = ILPStrategy(STRATEGY).pool();
        ammAdapter =
            ICAmmAdapter(IPlatform(PLATFORM).ammAdapter(keccak256(bytes(ILPStrategy(STRATEGY).ammAdapterId()))).proxy);

        rebalanceHelper = new RebalanceHelper();
    }

    function test_RebalanceCalculation() public view {
        // Verify initial state
        assertTrue(IALM(STRATEGY).needRebalance(), "Should need rebalance");

        // Get current positions
        IALM.Position[] memory positions = IALM(STRATEGY).positions();
        console.log("Current positions count:", positions.length);

        // Calculate rebalance arguments
        (bool[] memory burnOldPositions, IALM.NewPosition[] memory newPositions) =
            rebalanceHelper.calcRebalanceArgs(STRATEGY, 100);

        // Validate burn old positions
        console.log("Burn flags length:", burnOldPositions.length);
        for (uint i = 0; i < burnOldPositions.length; i++) {
            assertTrue(burnOldPositions[i], "All positions should be marked for burn");
        }

        // Validate new positions
        console.log("New positions count:", newPositions.length);
        assertEq(newPositions.length, 2, "Should create 2 new positions");

        // Validate base position
        IALM.NewPosition memory basePosition = newPositions[0];
        console.log("Base position liquidity:", basePosition.liquidity);
        assertGt(basePosition.liquidity, 0, "Base position should have liquidity");
        console.logInt(basePosition.tickLower);
        console.logInt(basePosition.tickUpper);

        // Validate fill-up position
        IALM.NewPosition memory fillUpPosition = newPositions[1];
        console.log("Fill-up position liquidity:", fillUpPosition.liquidity);
        assertGt(fillUpPosition.liquidity, 0, "Fill-up position should have liquidity");
        console.logInt(fillUpPosition.tickLower);
        console.logInt(fillUpPosition.tickUpper);

        // Verify tick alignment
        int24 tickSpacing = ALMLib.getUniswapV3TickSpacing(pool);
        assertEq(
            (basePosition.tickUpper - basePosition.tickLower) % tickSpacing,
            0,
            "Base position ticks should align with spacing"
        );
        assertEq(
            (fillUpPosition.tickUpper - fillUpPosition.tickLower) % tickSpacing,
            0,
            "Fill-up position ticks should align with spacing"
        );
    }

    function test_RebalanceParameters() public view {
        (, IALM.NewPosition[] memory newPositions) = rebalanceHelper.calcRebalanceArgs(STRATEGY, 100);

        // Verify slippage protection
        (, uint[] memory amounts) = IStrategy(STRATEGY).assetsAmounts();
        uint totalAmount0 = newPositions[0].minAmount0 + newPositions[1].minAmount0;
        uint totalAmount1 = newPositions[0].minAmount1 + newPositions[1].minAmount1;

        assertApproxEqAbs(
            totalAmount0,
            amounts[0] * 99_900 / 100_000, // 0.1% slippage tolerance
            (amounts[0] * 100) / 100_000,
            "Total amount0 should respect slippage"
        );

        assertApproxEqAbs(
            totalAmount1,
            amounts[1] * 99_900 / 100_000, // 0.1% slippage tolerance
            (amounts[1] * 100) / 100_000,
            "Total amount1 should respect slippage"
        );
    }
}
