// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import "../../chains/SonicLib.sol";
import "../base/chains/SonicSetup.sol";

contract SwapperSonicTest is Test, SonicSetup {
    ISwapper public swapper;

    function setUp() public {
        _init();
        swapper = ISwapper(platform.swapper());
        _deal(SonicLib.TOKEN_wS, address(this), 1e18);
        IERC20(SonicLib.TOKEN_wS).approve(address(swapper), type(uint).max);
        IERC20(SonicLib.TOKEN_stS).approve(address(swapper), type(uint).max);
        IERC20(SonicLib.TOKEN_BEETS).approve(address(swapper), type(uint).max);
        IERC20(SonicLib.TOKEN_USDC).approve(address(swapper), type(uint).max);
    }

    function testSwaps() public {
        uint got;
        swapper.swap(SonicLib.TOKEN_wS, SonicLib.TOKEN_stS, 1e13, 1_000); // 1%
        got = IERC20(SonicLib.TOKEN_stS).balanceOf(address(this));
        swapper.swap(SonicLib.TOKEN_stS, SonicLib.TOKEN_BEETS, got, 1_000); // 1%
        got = IERC20(SonicLib.TOKEN_BEETS).balanceOf(address(this));
        swapper.swap(SonicLib.TOKEN_BEETS, SonicLib.TOKEN_USDC, got, 1_000); // 1%
        got = IERC20(SonicLib.TOKEN_USDC).balanceOf(address(this));

        // console.log(got);
    }
}
