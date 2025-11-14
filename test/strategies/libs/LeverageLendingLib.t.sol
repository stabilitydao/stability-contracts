// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ILeverageLendingStrategy} from "../../../src/interfaces/ILeverageLendingStrategy.sol";
import {LeverageLendingLib} from "../../../src/strategies/libs/LeverageLendingLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SonicConstantsLib} from "../../../chains/sonic/SonicConstantsLib.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SonicFarmMakerLib} from "../../../chains/sonic/SonicFarmMakerLib.sol";

contract LeverageLendingLibTests is Test {
    uint internal constant FORK_BLOCK = 55065335; // Nov-13-2025 03:53:58 AM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
    }

    function testGetFlashFee18() public view {
        // ------------------------------------- BalancerV2
        assertEq(
            LeverageLendingLib.getFlashFee18(
                SonicConstantsLib.BEETS_VAULT, uint(ILeverageLendingStrategy.FlashLoanKind.Default_0)
            ),
            300000000000000, // 0.0003 = 0.03%
            "beets v2"
        );

        // ------------------------------------- BalancerV3_1
        assertEq(
            LeverageLendingLib.getFlashFee18(
                SonicConstantsLib.BEETS_VAULT_V3, uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1)
            ),
            0,
            "beets v3 flash fee"
        );

        // ------------------------------------- UniswapV3_2
        assertEq(
            LeverageLendingLib.getFlashFee18(
                SonicConstantsLib.POOL_SHADOW_CL_USDC_WETH, uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2)
            ),
            1658 * 1e12, // 0.0001658 = 0.01658%
            "uniswap-v3 flash fee"
        );

        // ------------------------------------- AlgebraV4_3
        assertEq(
            LeverageLendingLib.getFlashFee18(
                SonicConstantsLib.POOL_ALGEBRA_WS_USDC, uint(ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3)
            ),
            5000 * 1e12, // 0.0005 = 0.05%
            "algebra-v4 flash fee"
        );
    }
}
