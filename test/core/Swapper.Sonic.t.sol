// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";

contract SwapperSonicTest is Test, SonicSetup {
    ISwapper public swapper;

    function setUp() public {
        _init();
        swapper = ISwapper(platform.swapper());
        _deal(SonicConstantsLib.TOKEN_WS, address(this), 1e18);
        IERC20(SonicConstantsLib.TOKEN_WS).approve(address(swapper), type(uint).max);
        IERC20(SonicConstantsLib.TOKEN_STS).approve(address(swapper), type(uint).max);
        IERC20(SonicConstantsLib.TOKEN_BEETS).approve(address(swapper), type(uint).max);
        IERC20(SonicConstantsLib.TOKEN_USDC).approve(address(swapper), type(uint).max);
    }

    function testSwaps() public {
        uint got;
        swapper.swap(SonicConstantsLib.TOKEN_WS, SonicConstantsLib.TOKEN_STS, 1e17, 1_000); // 1%
        got = IERC20(SonicConstantsLib.TOKEN_STS).balanceOf(address(this));
        swapper.swap(SonicConstantsLib.TOKEN_STS, SonicConstantsLib.TOKEN_BEETS, got, 1_000); // 1%
        got = IERC20(SonicConstantsLib.TOKEN_BEETS).balanceOf(address(this));
        swapper.swap(SonicConstantsLib.TOKEN_BEETS, SonicConstantsLib.TOKEN_USDC, got, 1_000); // 1%
        got = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this));

        // console.log(got);
    }

    function testViews() public view {
        assertGt(swapper.allAssets().length, 0);
    }
}
