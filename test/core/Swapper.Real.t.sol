// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import "../../chains/RealLib.sol";
import "../base/chains/RealSetup.sol";

contract SwapperRealTest is Test, RealSetup {
    ISwapper public swapper;

    function setUp() public {
        _init();
        swapper = ISwapper(platform.swapper());
        _deal(RealLib.TOKEN_USDC, address(this), 1000e6);
        IERC20(RealLib.TOKEN_USDC).approve(address(swapper), type(uint).max);
        IERC20(RealLib.TOKEN_DAI).approve(address(swapper), type(uint).max);
        IERC20(RealLib.TOKEN_USTB).approve(address(swapper), type(uint).max);
        IERC20(RealLib.TOKEN_MORE).approve(address(swapper), type(uint).max);
        IERC20(RealLib.TOKEN_WREETH).approve(address(swapper), type(uint).max);
        IERC20(RealLib.TOKEN_PEARL).approve(address(swapper), type(uint).max);
        IERC20(RealLib.TOKEN_CVR).approve(address(swapper), type(uint).max);
        IERC20(RealLib.TOKEN_UKRE).approve(address(swapper), type(uint).max);
        IERC20(RealLib.TOKEN_RWA).approve(address(swapper), type(uint).max);
    }

    function testSwaps() public {
        uint got;
        swapper.swap(RealLib.TOKEN_USDC, RealLib.TOKEN_DAI, 100e6, 1_000); // 1%
        got = IERC20(RealLib.TOKEN_DAI).balanceOf(address(this));
        swapper.swap(RealLib.TOKEN_DAI, RealLib.TOKEN_USTB, got, 1_000); // 1%
        got = IERC20(RealLib.TOKEN_USTB).balanceOf(address(this));
        swapper.swap(RealLib.TOKEN_USTB, RealLib.TOKEN_MORE, got, 1_000); // 1%
        got = IERC20(RealLib.TOKEN_MORE).balanceOf(address(this));
        swapper.swap(RealLib.TOKEN_MORE, RealLib.TOKEN_WREETH, got, 1_000); // 1%
        got = IERC20(RealLib.TOKEN_WREETH).balanceOf(address(this));
        swapper.swap(RealLib.TOKEN_WREETH, RealLib.TOKEN_PEARL, got, 1_000); // 1%
        got = IERC20(RealLib.TOKEN_PEARL).balanceOf(address(this));
        swapper.swap(RealLib.TOKEN_PEARL, RealLib.TOKEN_CVR, got, 1_000); // 1%
        got = IERC20(RealLib.TOKEN_CVR).balanceOf(address(this));
        swapper.swap(RealLib.TOKEN_CVR, RealLib.TOKEN_UKRE, got, 1_000); // 1%
        got = IERC20(RealLib.TOKEN_UKRE).balanceOf(address(this));
        swapper.swap(RealLib.TOKEN_UKRE, RealLib.TOKEN_RWA, got, 1_000); // 1%
        got = IERC20(RealLib.TOKEN_RWA).balanceOf(address(this));
        // console.log(got);
        // swapper.swap(RealLib.TOKEN_RWA, RealLib.TOKEN_USDC, got/5, 1_000); // 1%
    }
}
