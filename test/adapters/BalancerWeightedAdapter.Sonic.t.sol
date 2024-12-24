// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/SonicSetup.sol";

contract BalancerWeightedAdapterTest is SonicSetup {
    bytes32 public _hash;
    IAmmAdapter public adapter;

    constructor() {
        _init();
        _hash = keccak256(bytes(AmmAdapterIdLib.BALANCER_WEIGHTED));
        adapter = IAmmAdapter(platform.ammAdapter(_hash).proxy);
        // console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.BalancerWeightedAdapter")) - 1)) & ~bytes32(uint256(0xff)));
    }

    function testIBalancerAdapter() public {
        IBalancerAdapter balancerAdapter = IBalancerAdapter(address(adapter));
        vm.expectRevert(IControllable.AlreadyExist.selector);
        balancerAdapter.setupHelpers(address(1));

        address pool = SonicLib.POOL_BEETHOVENX_BEETS_stS;
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
        address pool = SonicLib.POOL_BEETHOVENX_BEETS_stS;
        deal(SonicLib.TOKEN_stS, address(adapter), 1e15);
        adapter.swap(pool, SonicLib.TOKEN_stS, SonicLib.TOKEN_BEETS, address(this), 10_000);
        uint out = IERC20(SonicLib.TOKEN_BEETS).balanceOf(address(this));
        assertGt(out, 0);
        // console.log(out);
        deal(SonicLib.TOKEN_stS, address(adapter), 8000e18);
        vm.expectRevert();
        adapter.swap(pool, SonicLib.TOKEN_stS, SonicLib.TOKEN_BEETS, address(this), 10);
        // out = IERC20(SonicLib.TOKEN_stS).balanceOf(address(this));
        // console.log(out);
    }

    function testViewMethods() public view {
        assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash);

        address pool = SonicLib.POOL_BEETHOVENX_BEETS_stS;
        address[] memory tokens = adapter.poolTokens(pool);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], SonicLib.TOKEN_BEETS);
        assertEq(tokens[1], SonicLib.TOKEN_stS);

        uint[] memory props = adapter.getProportions(pool);
        assertEq(props[0], 8e17);
        assertEq(props[1], 2e17);
        // console.log(props[0]);
        // console.log(props[1]);

        uint price;
        price = adapter.getPrice(pool, SonicLib.TOKEN_BEETS, SonicLib.TOKEN_stS, 1e18);
        assertGt(price, 1e8);
        // console.log(price);

        assertEq(adapter.supportsInterface(type(IAmmAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IBalancerAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IERC165).interfaceId), true);
    }
}
