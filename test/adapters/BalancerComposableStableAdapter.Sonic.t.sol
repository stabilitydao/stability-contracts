// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {SonicLib, AmmAdapterIdLib, IBalancerAdapter} from "../../chains/SonicLib.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";

contract BalancerComposableStableAdapterTest is SonicSetup {
    bytes32 public _hash;
    IAmmAdapter public adapter;

    constructor() {
        _init();
        _hash = keccak256(bytes(AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE));
        adapter = IAmmAdapter(platform.ammAdapter(_hash).proxy);
        // console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.BalancerComposableStableAdapter")) - 1)) & ~bytes32(uint256(0xff)));
    }

    function testIBalancerAdapter() public {
        IBalancerAdapter balancerAdapter = IBalancerAdapter(address(adapter));
        vm.expectRevert(IControllable.AlreadyExist.selector);
        balancerAdapter.setupHelpers(address(1));

        address pool = SonicLib.POOL_BEETS_wS_stS;
        uint[] memory amounts = new uint[](2);
        amounts[0] = 1e18;
        amounts[1] = 100e18;
        (uint liquidity, uint[] memory amountsConsumed) = balancerAdapter.getLiquidityForAmountsWrite(pool, amounts);
        assertGt(liquidity, 1e10);
        assertEq(amountsConsumed[0], amounts[0]);
        assertEq(amountsConsumed[1], amounts[1]);
        // console.log(liquidity);
        // console.log(amountsConsumed[0]);
        // console.log(amountsConsumed[1]);
    }

    function testSwaps() public {
        address pool = SonicLib.POOL_BEETS_wS_stS;
        deal(SonicLib.TOKEN_wS, address(adapter), 1e16);
        adapter.swap(pool, SonicLib.TOKEN_wS, SonicLib.TOKEN_stS, address(this), 10_000);
        uint out = IERC20(SonicLib.TOKEN_stS).balanceOf(address(this));
        assertGt(out, 0);
        // console.log(out);
        deal(SonicLib.TOKEN_wS, address(adapter), 6e23);
        vm.expectRevert();
        adapter.swap(pool, SonicLib.TOKEN_wS, SonicLib.TOKEN_stS, address(this), 10);
        // out = IERC20(SonicLib.TOKEN_stS).balanceOf(address(this));
        // console.log(out);
    }

    function testViewMethods() public view {
        assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash);

        address pool = SonicLib.POOL_BEETS_wS_stS;
        uint price;
        price = adapter.getPrice(pool, SonicLib.TOKEN_stS, SonicLib.TOKEN_wS, 1e10);
        assertGt(price, 9e9);
        assertLt(price, 11e9);
        // console.log(price);

        address[] memory tokens = adapter.poolTokens(pool);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], SonicLib.TOKEN_wS);
        assertEq(tokens[1], SonicLib.TOKEN_stS);

        uint[] memory props = adapter.getProportions(pool);
        assertGt(props[0], 1e16);
        assertGt(props[1], 1e16);
        // console.log(props[0]);
        // console.log(props[1]);

        assertEq(adapter.supportsInterface(type(IAmmAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IBalancerAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IERC165).interfaceId), true);
    }
}
