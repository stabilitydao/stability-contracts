// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/SonicSetup.sol";
import "../../src/interfaces/ICAmmAdapter.sol";
import {AlgebraV4Adapter} from "../../src/adapters/AlgebraV4Adapter.sol";

contract AlgebraV4AdapterTest is SonicSetup {
    bytes32 public _hash;
    ICAmmAdapter public adapter;

    constructor() {
        //vm.rollFork(2702000); // Jan-06-2025 11:41:18 AM +UTC
        _init();
        _hash = keccak256(bytes(AmmAdapterIdLib.ALGEBRA_V4));
        adapter = ICAmmAdapter(platform.ammAdapter(_hash).proxy);
    }

    function testSwaps() public {
        address pool = SonicLib.POOL_SWAPX_CL_wS_SACRA;
        deal(SonicLib.TOKEN_wS, address(adapter), 1e16);
        adapter.swap(pool, SonicLib.TOKEN_wS, SonicLib.TOKEN_SACRA, address(this), 10_000);
        uint out = IERC20(SonicLib.TOKEN_SACRA).balanceOf(address(this));
        assertGt(out, 0);
        // console.log(out);
        deal(SonicLib.TOKEN_wS, address(adapter), 6e23);
        vm.expectRevert();
        adapter.swap(pool, SonicLib.TOKEN_wS, SonicLib.TOKEN_SACRA, address(this), 10);
        // out = IERC20(SonicLib.TOKEN_stS).balanceOf(address(this));
        // console.log(out);
    }

    function testReverts() public {
        vm.expectRevert();
        AlgebraV4Adapter(address(adapter)).algebraSwapCallback(0, 0, "");

        vm.expectRevert();
        adapter.getLiquidityForAmounts(address(0), new uint[](0));
    }

    function testViewMethods() public view {
        assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash);

        address pool = SonicLib.POOL_SWAPX_CL_wS_SACRA;
        uint price;
        price = adapter.getPrice(pool, SonicLib.TOKEN_SACRA, SonicLib.TOKEN_wS, 1e10);
        assertGt(price, 0);
        //console.log(price);

        address[] memory tokens = adapter.poolTokens(pool);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], SonicLib.TOKEN_wS);
        assertEq(tokens[1], SonicLib.TOKEN_SACRA);

        uint[] memory props = adapter.getProportions(pool);
        assertGt(props[0], 1e17);
        assertGt(props[1], 1e17);
        //console.log(props[0]);
        //console.log(props[1]);

        int24[] memory ticks = new int24[](2);
        ticks[0] = 28320;
        ticks[1] = 41700;
        props = adapter.getProportions(pool, ticks);
        assertGt(props[0], 1e17);
        assertGt(props[1], 1e17);
        //console.log(props[0]);
        //console.log(props[1]);

        uint[] memory amounts = new uint[](2);
        amounts[0] = 1e6;
        amounts[1] = 2e6;

        (uint liquidity, uint[] memory amountsConsumed) = adapter.getLiquidityForAmounts(pool, amounts, ticks);
        assertGt(liquidity, 0);
        assertGt(amountsConsumed[0], 0);
        assertGt(amountsConsumed[1], 0);

        uint[] memory liquidityAmounts = adapter.getAmountsForLiquidity(pool, ticks, uint128(liquidity));
        assertGt(liquidityAmounts[0], 0);
        assertGt(liquidityAmounts[1], 0);

        price = adapter.getPriceAtTick(pool, SonicLib.TOKEN_SACRA, 28320);
        assertGt(price, 0);

        assertEq(adapter.supportsInterface(type(IAmmAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(ICAmmAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IERC165).interfaceId), true);
    }
}
