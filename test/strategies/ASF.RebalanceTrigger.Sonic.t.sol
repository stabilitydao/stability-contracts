// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";
import {ALMLib} from "../../chains/sonic/SonicLib.sol";
import {RebalanceHelper} from "../../src/periphery/RebalanceHelper.sol";
import {IALM} from "../../src/interfaces/IALM.sol";
import {ILPStrategy} from "../../src/interfaces/ILPStrategy.sol";
import {IUniswapV3PoolImmutables} from "../../src/integrations/uniswapv3/pool/IUniswapV3PoolImmutables.sol";
import {IUniswapV3PoolState} from "../../src/integrations/uniswapv3/pool/IUniswapV3PoolState.sol";

contract RebalanceTriggerTest is Test {
    RebalanceHelper public rebalanceHelper;

    uint internal constant FORK_BLOCK = 18553912; // Mar-14-2025 07:49:27 AM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        rebalanceHelper = new RebalanceHelper();
    }

    // // Additional test cases
    function testNonALMStrategy() public {
        // Mock a contract that does not implement the IALM interface
        address nonALMStrategy = address(new MockNonALMStrategy());

        // Expect the call to revert with NotALM error
        vm.expectRevert(IALM.NotALM.selector);
        rebalanceHelper.calcRebalanceArgs(nonALMStrategy, 10);
    }

    function testNeedRebalance_LimitPosition_NoMove() public {
        IALM.AlmStrategyBaseStorage storage almStrategy;
        ILPStrategy.LpStrategyBaseStorage storage lpStrategy;

        bytes32 alm_strategy_location = 0xa7b5cf2e827fe3bcf3fe6a0f3315b77285780eac3248f46a43fc1c44c1d47900;
        bytes32 lp_strategy_location = 0x72189c387e876b9a88f41e18ce5929a30f87f78bd01fd02027d49c1ff673554f;

        assembly {
            almStrategy.slot := alm_strategy_location
            lpStrategy.slot := lp_strategy_location
        }

        almStrategy.algoId = ALMLib.ALGO_FILL_UP;
        almStrategy.params = new int24[](2);
        almStrategy.params[0] = 1000;
        almStrategy.params[1] = 200;

        almStrategy.positions.push();
        almStrategy.positions[0].tickLower = 1000;
        almStrategy.positions[0].tickUpper = 2000;
        almStrategy.positions.push();
        almStrategy.positions[1].tickLower = 1000;
        almStrategy.positions[1].tickUpper = 2000;

        address pool = lpStrategy.pool;
        int24 tickSpacing = 10;
        vm.mockCall(
            pool, abi.encodeWithSelector(IUniswapV3PoolImmutables.tickSpacing.selector), abi.encode(tickSpacing)
        );

        int24 currentTick = 1500;
        vm.mockCall(
            pool,
            abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
            abi.encode(uint160(0), currentTick, uint16(0), uint16(0), uint16(0), uint8(0), bool(false))
        );

        bool need = ALMLib.needRebalance(almStrategy, lpStrategy);
        assertFalse(need, "Should NOT need rebalance when tickDistance == 0");
    }

    function testNeedRebalance_BasePositionTrigger() public {
        IALM.AlmStrategyBaseStorage storage almStrategy;
        ILPStrategy.LpStrategyBaseStorage storage lpStrategy;

        bytes32 alm_strategy_location = 0xa7b5cf2e827fe3bcf3fe6a0f3315b77285780eac3248f46a43fc1c44c1d47900;
        bytes32 lp_strategy_location = 0x72189c387e876b9a88f41e18ce5929a30f87f78bd01fd02027d49c1ff673554f;

        assembly {
            almStrategy.slot := alm_strategy_location
            lpStrategy.slot := lp_strategy_location
        }

        almStrategy.algoId = ALMLib.ALGO_FILL_UP;
        almStrategy.params = new int24[](2);
        almStrategy.params[0] = 1000; // range
        almStrategy.params[1] = 200; // trigger range

        almStrategy.positions.push();
        almStrategy.positions[0].tickLower = -500;
        almStrategy.positions[0].tickUpper = 500;

        address pool = lpStrategy.pool;
        int24 tickSpacing = 10;
        vm.mockCall(
            pool, abi.encodeWithSelector(IUniswapV3PoolImmutables.tickSpacing.selector), abi.encode(tickSpacing)
        );

        int24 currentTick = 700; // triggers fillUpRebalance
        vm.mockCall(
            pool,
            abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
            abi.encode(uint160(0), currentTick, uint16(0), uint16(0), uint16(0), uint8(0), bool(false))
        );

        bool need = ALMLib.needRebalance(almStrategy, lpStrategy);
        assertTrue(need, "Should trigger base position rebalance");
    }

    function testNeedRebalance_UnsupportedAlgo() public {
        IALM.AlmStrategyBaseStorage storage almStrategy;
        ILPStrategy.LpStrategyBaseStorage storage lpStrategy;

        bytes32 alm_strategy_location = 0xa7b5cf2e827fe3bcf3fe6a0f3315b77285780eac3248f46a43fc1c44c1d47900;
        bytes32 lp_strategy_location = 0x72189c387e876b9a88f41e18ce5929a30f87f78bd01fd02027d49c1ff673554f;

        assembly {
            almStrategy.slot := alm_strategy_location
            lpStrategy.slot := lp_strategy_location
        }

        almStrategy.algoId = 0;
        almStrategy.params = new int24[](2);
        address pool = lpStrategy.pool;

        // Still mock so the call doesn't revert
        vm.mockCall(pool, abi.encodeWithSelector(IUniswapV3PoolImmutables.tickSpacing.selector), abi.encode(int24(10)));

        bool need = ALMLib.needRebalance(almStrategy, lpStrategy);
        assertFalse(need, "Should NOT rebalance if algoId is not ALGO_FILL_UP");
    }

    function testNeedRebalance_LimitPosition_MoveBelow1() public {
        IALM.AlmStrategyBaseStorage storage almStrategy;
        ILPStrategy.LpStrategyBaseStorage storage lpStrategy;

        bytes32 alm_strategy_location = 0xa7b5cf2e827fe3bcf3fe6a0f3315b77285780eac3248f46a43fc1c44c1d47900;
        bytes32 lp_strategy_location = 0x72189c387e876b9a88f41e18ce5929a30f87f78bd01fd02027d49c1ff673554f;

        assembly {
            almStrategy.slot := alm_strategy_location
            lpStrategy.slot := lp_strategy_location
        }

        almStrategy.algoId = ALMLib.ALGO_FILL_UP;
        almStrategy.params = new int24[](2);
        almStrategy.params[0] = 1000;
        almStrategy.params[1] = 200;

        almStrategy.positions.push();
        almStrategy.positions[0].tickLower = 1000;
        almStrategy.positions[0].tickUpper = 2000;
        almStrategy.positions.push();
        almStrategy.positions[1].tickLower = 1600;
        almStrategy.positions[1].tickUpper = 2000;

        address pool = lpStrategy.pool;
        int24 tickSpacing = 10;
        vm.mockCall(
            pool, abi.encodeWithSelector(IUniswapV3PoolImmutables.tickSpacing.selector), abi.encode(tickSpacing)
        );

        int24 currentTick = 1500; // below limitTickLower
        vm.mockCall(
            pool,
            abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
            abi.encode(uint160(0), currentTick, uint16(0), uint16(0), uint16(0), uint8(0), bool(false))
        );

        bool need = ALMLib.needRebalance(almStrategy, lpStrategy);
        assertTrue(need, "Should need rebalance when currentTick is below limitTickLower");
    }

    function testNeedRebalance_LimitPosition_MoveBelow2() public {
        IALM.AlmStrategyBaseStorage storage almStrategy;
        ILPStrategy.LpStrategyBaseStorage storage lpStrategy;

        bytes32 alm_strategy_location = 0xa7b5cf2e827fe3bcf3fe6a0f3315b77285780eac3248f46a43fc1c44c1d47900;
        bytes32 lp_strategy_location = 0x72189c387e876b9a88f41e18ce5929a30f87f78bd01fd02027d49c1ff673554f;

        assembly {
            almStrategy.slot := alm_strategy_location
            lpStrategy.slot := lp_strategy_location
        }

        almStrategy.algoId = ALMLib.ALGO_FILL_UP;
        almStrategy.params = new int24[](2);
        almStrategy.params[0] = 1000;
        almStrategy.params[1] = 200;

        almStrategy.positions.push();
        almStrategy.positions[0].tickLower = 1000;
        almStrategy.positions[0].tickUpper = 2000;
        almStrategy.positions.push();
        almStrategy.positions[1].tickLower = 1000;
        almStrategy.positions[1].tickUpper = 1400;

        address pool = lpStrategy.pool;
        int24 tickSpacing = 10;
        vm.mockCall(
            pool, abi.encodeWithSelector(IUniswapV3PoolImmutables.tickSpacing.selector), abi.encode(tickSpacing)
        );

        int24 currentTick = 1500; // ABOVE limitTickUpper
        vm.mockCall(
            pool,
            abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
            abi.encode(uint160(0), currentTick, uint16(0), uint16(0), uint16(0), uint8(0), bool(false))
        );

        bool need = ALMLib.needRebalance(almStrategy, lpStrategy);
        assertTrue(need, "Should need rebalance when currentTick is below limitTickLower");
    }
}

// Mock contract that does not implement the IALM interface
contract MockNonALMStrategy is IERC165 {
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId; // Only supports IERC165, not IALM
    }
}
