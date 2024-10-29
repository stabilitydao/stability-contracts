// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../src/interfaces/IAmmAdapter.sol";
import "../../src/adapters/libs/AmmAdapterIdLib.sol";
import "../base/chains/PolygonSetup.sol";

contract CurveAdapterTest is PolygonSetup {
    bytes32 public _hash;
    ICAmmAdapter adapter;

    constructor() {
        vm.rollFork(55628000); // Apr-09-2024 01:21:45 PM +UTC
        _init();
        _hash = keccak256(bytes(AmmAdapterIdLib.CURVE));
        adapter = ICAmmAdapter(platform.ammAdapter(_hash).proxy);
    }

    function testViewMethods() public view {
        assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash);
        address pool = PolygonLib.POOL_CURVE_crvUSD_USDCe;
        address[] memory poolTokens = adapter.poolTokens(pool);
        assertEq(poolTokens.length, 2);
        assertEq(poolTokens[0], PolygonLib.TOKEN_crvUSD);
        assertEq(poolTokens[1], PolygonLib.TOKEN_USDCe);

        uint[] memory props = adapter.getProportions(pool);
        assertEq(props.length, 2);
        assertGt(props[0], 1e17);
        assertGt(props[1], 1e17);
        assertGe(props[0] + props[1], 1e18 - 1);
        assertLe(props[0] + props[1], 1e18 + 1);

        uint price = adapter.getPrice(pool, PolygonLib.TOKEN_crvUSD, PolygonLib.TOKEN_USDCe, 1e18);
        assertGt(price, 9e5);
        assertLt(price, 11e5);

        uint[] memory amounts = new uint[](2);
        amounts[0] = 1e18 - 132323213;
        amounts[1] = 11e6 + 9313;
        (uint liquidity, uint[] memory amountsConsumed) = adapter.getLiquidityForAmounts(pool, amounts);
        assertGt(liquidity, 0);
        assertEq(amountsConsumed.length, amounts.length);
        assertEq(amountsConsumed[0], amounts[0]);
        assertEq(amountsConsumed[1], amounts[1]);

        assertEq(adapter.supportsInterface(type(IAmmAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IERC165).interfaceId), true);
    }

    function testSwaps() public {
        deal(PolygonLib.TOKEN_USDCe, address(adapter), 1000e6);
        adapter.swap(
            PolygonLib.POOL_CURVE_crvUSD_USDCe, PolygonLib.TOKEN_USDCe, PolygonLib.TOKEN_crvUSD, address(this), 1_000
        );
        uint out = IERC20(PolygonLib.TOKEN_crvUSD).balanceOf(address(this));
        assertEq(out, 1003257188385627452801);
        deal(PolygonLib.TOKEN_crvUSD, address(adapter), 30000e18);
        vm.expectRevert(bytes("!PRICE 425"));
        adapter.swap(
            PolygonLib.POOL_CURVE_crvUSD_USDCe, PolygonLib.TOKEN_crvUSD, PolygonLib.TOKEN_USDCe, address(this), 100
        );
    }
}
