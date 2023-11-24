// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../src/interfaces/ICAmmAdapter.sol";
import "../../src/adapters/libs/AmmAdapterIdLib.sol";
import "../base/chains/PolygonSetup.sol";

contract KyberAdapterTest is PolygonSetup {
    bytes32 public _hash;
    ICAmmAdapter adapter;

    constructor() {
        _init();
        _hash = keccak256(bytes(AmmAdapterIdLib.KYBER));
        adapter = ICAmmAdapter(platform.ammAdapter(_hash).proxy);
    }

    function testViewMethods() public {
        assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash);

        vm.expectRevert(IAmmAdapter.NotSupportedByCAMM.selector);
        adapter.getLiquidityForAmounts(address(0), new uint[](2));

        address pool = PolygonLib.POOL_KYBER_USDC_USDT;
        uint[] memory amounts = new uint[](2);
        amounts[0] = 1e6;
        amounts[1] = 2e6;
        int24[] memory ticks = new int24[](2);
        ticks[0] = -60;
        ticks[1] = 60;

        (uint liquidity, uint[] memory amountsConsumed) = adapter.getLiquidityForAmounts(pool, amounts, ticks);
        assertGt(liquidity, 0);
        assertGt(amountsConsumed[0], 0);
        assertGt(amountsConsumed[1], 0);

        uint[] memory liquidityAmounts = adapter.getAmountsForLiquidity(pool, ticks, uint128(liquidity));
        assertGt(liquidityAmounts[0], 0);
        assertGt(liquidityAmounts[1], 0);

        // (uint amount0, uint amount1) = UniswapV3Adapter(address(adapter)).getAmountsForLiquidity(pool, ticks[0], ticks[1], uint128(liquidity));
        // assertEq(liquidityAmounts[0], amount0);
        // assertEq(liquidityAmounts[1], amount1);

        uint[] memory proportions = adapter.getProportions(pool);
        assertGt(proportions[0], 0);
        assertGt(proportions[1], 0);

        uint prop0 = adapter.getProportion0(pool);
        assertEq(prop0, proportions[0]);

        uint price;

        price = adapter.getPriceAtTick(PolygonLib.POOL_KYBER_USDC_DAI, PolygonLib.TOKEN_USDC, 276240);
        assertEq(price, 991632976171952929);
        // console.log(price);
        price = adapter.getPriceAtTick(PolygonLib.POOL_KYBER_USDC_DAI, PolygonLib.TOKEN_DAI, 276240);
        assertEq(price, 1008437);
        // console.log(price);

        vm.expectRevert(IAmmAdapter.WrongCallbackAmount.selector);
        KyberAdapter(address(adapter)).swapCallback(0, 0, '');
    }

}
