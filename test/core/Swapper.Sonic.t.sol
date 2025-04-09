// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import "../../chains/sonic/SonicLib.sol";
import "../base/chains/SonicSetup.sol";

contract SwapperSonicTest is Test, SonicSetup {
    ISwapper public swapper;

    function setUp() public {
        _init();
        swapper = ISwapper(platform.swapper());
        _deal(SonicConstantsLib.TOKEN_wS, address(this), 1e18);
        IERC20(SonicConstantsLib.TOKEN_wS).approve(address(swapper), type(uint).max);
        IERC20(SonicConstantsLib.TOKEN_stS).approve(address(swapper), type(uint).max);
        IERC20(SonicConstantsLib.TOKEN_BEETS).approve(address(swapper), type(uint).max);
        IERC20(SonicConstantsLib.TOKEN_USDC).approve(address(swapper), type(uint).max);
    }

    function testSwaps() public {
        uint got;
        swapper.swap(SonicConstantsLib.TOKEN_wS, SonicConstantsLib.TOKEN_stS, 1e17, 1_000); // 1%
        got = IERC20(SonicConstantsLib.TOKEN_stS).balanceOf(address(this));
        swapper.swap(SonicConstantsLib.TOKEN_stS, SonicConstantsLib.TOKEN_BEETS, got, 1_000); // 1%
        got = IERC20(SonicConstantsLib.TOKEN_BEETS).balanceOf(address(this));
        swapper.swap(SonicConstantsLib.TOKEN_BEETS, SonicConstantsLib.TOKEN_USDC, got, 1_000); // 1%
        got = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this));

        // console.log(got);
    }
}
