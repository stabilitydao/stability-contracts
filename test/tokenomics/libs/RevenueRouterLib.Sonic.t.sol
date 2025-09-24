// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/console.sol";
import {SonicConstantsLib} from "../../../chains/sonic/SonicConstantsLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPlatform} from "../../../src/interfaces/IPlatform.sol";
import {ISwapper} from "../../../src/interfaces/ISwapper.sol";
import {RevenueRouterLib} from "../../../src/tokenomics/libs/RevenueRouterLib.sol";
import {Test} from "forge-std/Test.sol";
import {MockRecovery} from "../../../src/test/MockRecovery.sol";

contract RevenueRouterLibSonicTest is Test {
    uint public constant FORK_BLOCK = 47846991; // Sep-23-2025 02:52:36 AM +UTC

    struct RemoveEmptyTestCase {
        uint[5] amounts;
        uint countNotZero;

        address[] expectedAssets;
        uint[] expectedAmounts;
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
    }

    //region --------------------------- processAssets
    function testProcessAssets() public {
        ISwapper swapper = ISwapper(IPlatform(SonicConstantsLib.PLATFORM).swapper());
        address multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();

        // -------------------- prepare assets: usdc, weth, stbl, usdt, wbtc
        address[] memory assets = new address[](5);
        assets[0] = SonicConstantsLib.TOKEN_USDC;
        assets[1] = SonicConstantsLib.TOKEN_WETH;
        assets[2] = SonicConstantsLib.TOKEN_STBL;
        assets[3] = SonicConstantsLib.TOKEN_USDT;
        assets[4] = SonicConstantsLib.TOKEN_WS;

        uint[] memory amounts = new uint[](5);
        amounts[0] = 1_000e6; // usdc
        amounts[1] = 1e18;    // weth:  amount is equal to the threshold
        amounts[2] = 10e18;   // stbl
        amounts[3] = 100;     // usdt:  amount is below the threshold
        amounts[4] = 0.1e18;  // ws

        for (uint i; i < assets.length; ++i) {
            deal(assets[i], address(this), amounts[i]);
        }

        // -------------------- set up thresholds
        {
            uint[] memory thresholds = new uint[](5);
            thresholds[0] = 500e6; // usdc
            thresholds[1] = 1e18; // weth
            thresholds[2] = 9e18; // stbl
            thresholds[3] = 50e6; // usdt
            thresholds[4] = 0.05e18; // ws

            vm.prank(multisig);
            swapper.setThresholds(assets, thresholds);
        }

        // -------------------- process assets
        MockRecovery recovery = new MockRecovery();
        RevenueRouterLib.processAssets(assets, SonicConstantsLib.TOKEN_STBL, swapper, address(recovery));

        // -------------------- check recoverContract balances
        {
            uint[] memory balances = new uint[](5);
            for (uint i; i < assets.length; ++i) {
                balances[i] = IERC20(assets[i]).balanceOf(address(recovery));
            }

            for (uint i; i < assets.length; ++i) {
                if (i == 1 || i == 3 || i == 2) {
                     assertEq(balances[i], 0, "weth, usdt - below threshold, stbl - not processed as income");
                } else {
                    assertEq(balances[i], amounts[i] * RevenueRouterLib.RECOVER_PERCENTAGE / RevenueRouterLib.DENOMINATOR, "get 20% of income");
                }
            }

            assertEq(recovery.registeredTokensLength(), 2, "expected amount of registered tokens");
            assertEq(recovery.registeredTokens(0), SonicConstantsLib.TOKEN_USDC, "expected USDC");
            assertEq(recovery.registeredTokens(1), SonicConstantsLib.TOKEN_WS, "expected WS");
        }

        // -------------------- check sender balances
        {
            uint[] memory balances = new uint[](5);
            for (uint i; i < assets.length; ++i) {
                balances[i] = IERC20(assets[i]).balanceOf(address(this));
            }

            for (uint i; i < assets.length; ++i) {
                if (i == 1 || i == 3) {
                     assertEq(balances[i], amounts[i], "weth, usdt - below threshold");
                } else if (i == 0 || i == 4) {
                    // usdc, ws - swapped to stbl
                    assertEq(balances[i], 0, "usdc, ws - swapped to stbl");
                } else if (i == 2) {
                    // stbl - not processed as income
                    assertGt(balances[i], amounts[i], "usdc and ws were swapped to stbl, balance should be greater than initial");
                } else {
                    revert("unexpected asset");
                }
            }
        }
    }

    function testProcessAssetsEmpty() public {
        ISwapper swapper = ISwapper(IPlatform(SonicConstantsLib.PLATFORM).swapper());
        address multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();

        // -------------------- prepare assets: usdc, weth, stbl, usdt, wbtc
        address[] memory assets = new address[](1);
        assets[0] = SonicConstantsLib.TOKEN_USDC;

        uint[] memory amounts = new uint[](5);
        amounts[0] = 0.1e6; // usdc: below threshold

        for (uint i; i < assets.length; ++i) {
            deal(assets[i], address(this), amounts[i]);
        }

        // -------------------- set up thresholds
        {
            uint[] memory thresholds = new uint[](1);
            thresholds[0] = 1e6; // usdc

            vm.prank(multisig);
            swapper.setThresholds(assets, thresholds);
        }

        // -------------------- process assets
        MockRecovery _recovery = new MockRecovery();
        RevenueRouterLib.processAssets(assets, SonicConstantsLib.TOKEN_STBL, swapper, address(_recovery));

        // -------------------- check recoverContract balances
        for (uint i; i < assets.length; ++i) {
            uint balance = IERC20(assets[i]).balanceOf(address(_recovery));
            assertEq(balance, 0, "nothing was earned");
        }

        assertEq(_recovery.registeredTokensLength(), 0, "expected amount of registered tokens");

        // -------------------- check sender balances
        for (uint i; i < assets.length; ++i) {
            uint balance = IERC20(assets[i]).balanceOf(address(this));
            assertEq(balance, amounts[i], "initial balance wasn't changed");
        }
    }

    //endregion --------------------------- processAssets

    //region --------------------------- removeEmpty
    function fixtureCases() public pure returns (RemoveEmptyTestCase[] memory t) {
        t = new RemoveEmptyTestCase[](3);

        // -------------------- two random items are not zero
        t[0] = RemoveEmptyTestCase({
            amounts: [uint(0), 100, 0, 200, 0],
            countNotZero: 2,
            expectedAssets: new address[](2),
            expectedAmounts: new uint[](2)
        });
        t[0].expectedAssets[0] = address(2);
        t[0].expectedAssets[1] = address(4);
        t[0].expectedAmounts[0] = 100;
        t[0].expectedAmounts[1] = 200;

        // -------------------- only two first items are not zero
        t[1] = RemoveEmptyTestCase({
            amounts: [uint(10), 20, 0, 0, 0],
            countNotZero: 2,
            expectedAssets: new address[](2),
            expectedAmounts: new uint[](2)
        });
        t[1].expectedAssets[0] = address(1);
        t[1].expectedAssets[1] = address(2);
        t[1].expectedAmounts[0] = 10;
        t[1].expectedAmounts[1] = 20;

        // -------------------- only two last items are not zero
        t[2] = RemoveEmptyTestCase({
            amounts: [uint(0), 0, 0, 300, 400],
            countNotZero: 2,
            expectedAssets: new address[](2),
            expectedAmounts: new uint[](2)
        });
        t[2].expectedAssets[0] = address(4);
        t[2].expectedAssets[1] = address(5);
        t[2].expectedAmounts[0] = 300;
        t[2].expectedAmounts[1] = 400;
    }

    function tableRemoveEmptyCasesTest(RemoveEmptyTestCase memory cases) public pure {
        address[] memory assets = new address[](5);
        uint[] memory amounts = new uint[](5);

        for (uint i = 0; i < 5; i++) {
            assets[i] = address(uint160(i + 1));
            amounts[i] = cases.amounts[i];
        }

        (address[] memory _assets, uint[] memory _amounts) = RevenueRouterLib.removeEmpty(assets, amounts, cases.countNotZero);

        assertEq(_assets.length, cases.expectedAssets.length);
        assertEq(_amounts.length, cases.expectedAmounts.length);
        for (uint i = 0; i < cases.expectedAssets.length; i++) {
            assertEq(_assets[i], cases.expectedAssets[i]);
            assertEq(_amounts[i], cases.expectedAmounts[i]);
        }
    }
    //endregion --------------------------- removeEmpty
}
