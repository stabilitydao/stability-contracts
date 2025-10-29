// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ICAmmAdapter} from "../../src/interfaces/ICAmmAdapter.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {PolygonSetup} from "../base/chains/PolygonSetup.sol";
import {PolygonLib} from "../../chains/PolygonLib.sol";
import {KyberAdapter} from "../../src/adapters/KyberAdapter.sol";

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

        address pool = PolygonLib.POOL_KYBER_USDCe_USDT;
        uint[] memory amounts = new uint[](2);
        amounts[0] = 1e6;
        amounts[1] = 2e6;
        int24[] memory ticks = new int24[](2);
        ticks[0] = -120 * 1000;
        ticks[1] = 120 * 1000;

        (uint liquidity, uint[] memory amountsConsumed) = adapter.getLiquidityForAmounts(pool, amounts, ticks);
        assertGt(liquidity, 0, "liquidity");
        assertGt(amountsConsumed[0], 0, "amountsConsumed[0]");
        assertGt(amountsConsumed[1], 0, "amountsConsumed[1]");

        uint[] memory liquidityAmounts = adapter.getAmountsForLiquidity(pool, ticks, uint128(liquidity));
        assertGt(liquidityAmounts[0], 0);
        assertGt(liquidityAmounts[1], 0);

        uint[] memory proportions = adapter.getProportions(pool);
        assertGt(proportions[0], 0, "props0");
        assertGt(proportions[1], 0, "props1");

        uint[] memory props = adapter.getProportions(pool, ticks);
        assertGt(props[0], 0, "props0 ticks");
        assertGt(props[1], 0, "props1 ticks");

        uint price;

        price = adapter.getPriceAtTick(PolygonLib.POOL_KYBER_USDCe_DAI, PolygonLib.TOKEN_USDCe, 276240);
        assertEq(price, 991632976172244213); // #252: calcPriceOut was changed, 991632976171952929);
        // console.log(price);
        price = adapter.getPriceAtTick(PolygonLib.POOL_KYBER_USDCe_DAI, PolygonLib.TOKEN_DAI, 276240);
        assertEq(price, 1008437);
        // console.log(price);

        vm.expectRevert(IAmmAdapter.WrongCallbackAmount.selector);
        KyberAdapter(address(adapter)).swapCallback(0, 0, "");

        assertEq(adapter.supportsInterface(type(ICAmmAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IAmmAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IERC165).interfaceId), true);
    }

    function testGetTwaPrice() public {
        vm.expectRevert("Not supported");
        adapter.getTwaPrice(address(0), address(0), address(0), 0, 0);
    }
}
