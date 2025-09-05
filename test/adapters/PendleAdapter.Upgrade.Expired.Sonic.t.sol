// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Test.sol";
import {ICAmmAdapter} from "../../src/interfaces/ICAmmAdapter.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {SonicSetup, SonicConstantsLib, IERC20} from "../base/chains/SonicSetup.sol";
import {PendleAdapter} from "../../src/adapters/PendleAdapter.sol";

contract PendleAdapterUpgradeExpiredTest is SonicSetup {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    bytes32 public _hash;
    ICAmmAdapter public adapter;

    constructor() {
        vm.rollFork(39816642); // Jul-23-2025 07:28:08 AM +UTC  expired
        // vm.rollFork(39959557); // Jul-24-2025 04:13:11 AM +UTC

        _init();
        _hash = keccak256(bytes(AmmAdapterIdLib.PENDLE));
        adapter = ICAmmAdapter(platform.ammAdapter(_hash).proxy);

        // we need to skip 1 day to update the swapper
        // but we cannot simply skip 1 day, because the silo oracle will start to revert with InvalidPrice
        vm.warp(block.timestamp - 86400);
    }

    function testSwapPtWstkscUSD29MAY2025() public {
        _upgradePlatform();

        address holder = 0x2fC82F6E988A8e2F21247cCE5dF117f40d5F8e82;

        uint price = adapter.getPrice(
            SonicConstantsLib.POOL_PENDLE_PT_wstkscUSD_29MAY2025,
            SonicConstantsLib.TOKEN_PT_wstkscUSD_29MAY2025,
            SonicConstantsLib.TOKEN_stkscUSD,
            11e6
        );

        // swap PT to yield token
        uint got = _swap(
            SonicConstantsLib.POOL_PENDLE_PT_wstkscUSD_29MAY2025,
            SonicConstantsLib.TOKEN_PT_wstkscUSD_29MAY2025,
            SonicConstantsLib.TOKEN_stkscUSD,
            11e6,
            holder
        );
        assertApproxEqAbs(got, price, 10, "wstkscUSD_29MAY2025: swap amount is same to price");
        assertApproxEqAbs(got, 11e6, 10, "wstkscUSD_29MAY2025: swap amount is not as expected");
    }

    function testSwapPtWstkscETHMAY2025() public {
        _upgradePlatform();

        address holder = 0xFFFC9d22304CF49784e9B31dDBEB066344b2B856;

        uint price = adapter.getPrice(
            SonicConstantsLib.POOL_PENDLE_PT_wstkscETH_29MAY2025,
            SonicConstantsLib.TOKEN_PT_wstkscETH_29MAY2025,
            SonicConstantsLib.TOKEN_stkscETH,
            11e18
        );
        console.log("price", price);

        // swap PT to yield token
        uint got = _swap(
            SonicConstantsLib.POOL_PENDLE_PT_wstkscETH_29MAY2025,
            SonicConstantsLib.TOKEN_PT_wstkscETH_29MAY2025,
            SonicConstantsLib.TOKEN_stkscETH,
            11e18,
            holder
        );
        assertApproxEqAbs(got, price, 10, "wstkscETH_29MAY2025: swap amount is same to price");
        assertApproxEqAbs(got, 11e18, 10, "wstkscETH_29MAY2025: swap amount is not as expected");
    }

    function testSwapPtwOSMAY2025() public {
        _upgradePlatform();

        address holder = 0x73E9f22012883e19521AA8060B0603D708BF4390;

        uint price = adapter.getPrice(
            SonicConstantsLib.POOL_PENDLE_PT_wOS_29MAY2025,
            SonicConstantsLib.TOKEN_PT_wOS_29MAY2025,
            SonicConstantsLib.TOKEN_OS,
            11e18
        );

        // swap PT to yield token
        uint got = _swap(
            SonicConstantsLib.POOL_PENDLE_PT_wOS_29MAY2025,
            SonicConstantsLib.TOKEN_PT_wOS_29MAY2025,
            SonicConstantsLib.TOKEN_OS,
            11e18,
            holder
        );

        assertApproxEqAbs(got, price, 10, "wOS_29MAY2025: swap amount is same to price");
        assertApproxEqAbs(got, 11e18, 10, "wOS_29MAY2025: swap amount is not as expected");
    }

    function testSwapSilo20Usdc17JUL2025() public {
        _upgradePlatform();

        address holder = 0x7336CE5F77631F4B6eb9ef16b85D35bf8F1CefE4;

        uint price = adapter.getPrice(
            SonicConstantsLib.POOL_PT_Silo_20_USDC_17JUL2025,
            SonicConstantsLib.TOKEN_PT_Silo_20_USDC_17JUL2025,
            SonicConstantsLib.TOKEN_USDC,
            11e6
        );

        // swap PT to yield token
        uint got = _swap(
            SonicConstantsLib.POOL_PT_Silo_20_USDC_17JUL2025,
            SonicConstantsLib.TOKEN_PT_Silo_20_USDC_17JUL2025,
            SonicConstantsLib.TOKEN_USDC,
            11e6,
            holder
        );

        assertApproxEqAbs(got, price, 1, "USDC_17JUL2025: swap amount is same to price");
        assertApproxEqAbs(got, 11e6, 1, "USDC_17JUL2025: swap amount is not as expected");
    }

    //region ------------------------------- Helpers
    function _swap(
        address pool,
        address tokenIn,
        address tokenOut,
        uint amount,
        address holder
    ) internal returns (uint) {
        uint balanceWas = IERC20(tokenOut).balanceOf(holder);

        vm.prank(holder);
        IERC20(tokenIn).transfer(address(adapter), amount);

        vm.prank(holder);
        adapter.swap(pool, tokenIn, tokenOut, holder, 1_000);

        return IERC20(tokenOut).balanceOf(holder) - balanceWas;
    }

    function _upgradePlatform() internal {
        address multisig = IPlatform(PLATFORM).multisig();

        address[] memory proxies = new address[](1);
        proxies[0] = IPlatform(PLATFORM).ammAdapter(keccak256(bytes(AmmAdapterIdLib.PENDLE))).proxy;

        address[] memory implementations = new address[](1);
        implementations[0] = address(new PendleAdapter());

        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.05.0-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
        vm.stopPrank();
    }
    //endregion ------------------------------- Helpers
}
