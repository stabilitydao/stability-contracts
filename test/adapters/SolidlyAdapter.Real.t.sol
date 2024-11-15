// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SolidlyAdapter} from "../../src/adapters/SolidlyAdapter.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {RealLib} from "../../chains/RealLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SolidlyAdapterTest is Test {
    address public constant PLATFORM = 0xB7838d447deece2a9A5794De0f342B47d0c1B9DC;
    IAmmAdapter public adapter;
    bytes32 public _hash;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("REAL_RPC_URL")));
        vm.rollFork(1132900); // Nov 15 2024
        _addAdapter();
    }

    function _addAdapter() internal {
        _hash = keccak256(bytes(AmmAdapterIdLib.SOLIDLY));
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new SolidlyAdapter()));
        adapter = IAmmAdapter(address(proxy));
        adapter.init(PLATFORM);
        string memory id = AmmAdapterIdLib.SOLIDLY;
        vm.prank(IPlatform(PLATFORM).multisig());
        IPlatform(PLATFORM).addAmmAdapter(id, address(proxy));
    }

    function testViewMethods() public view {
        assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash);

        uint[] memory amounts = new uint[](2);
        amounts[0] = 10e18;
        amounts[1] = 10e6;
        (uint liquidity, uint[] memory amountsConsumed) =
            adapter.getLiquidityForAmounts(RealLib.POOL_PEARL_MORE_USDC, amounts);
        assertGt(liquidity, 0);
        assertGt(amountsConsumed[0], 0);
        assertGt(amountsConsumed[1], 0);

        // 0.38 USDC for 1 MORE at this block
        uint price = adapter.getPrice(RealLib.POOL_PEARL_MORE_USDC, RealLib.TOKEN_MORE, RealLib.TOKEN_USDC, 1e18);
        assertGt(price, 380000);
        assertLt(price, 390000);

        // ~~ 74.1%/25.9%
        uint[] memory props = adapter.getProportions(RealLib.POOL_PEARL_MORE_USDC);
        assertGt(props[0], 74e16);
        assertLt(props[0], 75e16);

        adapter.poolTokens(RealLib.POOL_PEARL_MORE_USDC);
    }

    function testSwaps() public {
        deal(RealLib.TOKEN_USDC, address(adapter), 1000e6);
        adapter.swap(RealLib.POOL_PEARL_MORE_USDC, RealLib.TOKEN_USDC, RealLib.TOKEN_MORE, address(this), 1_000);
        uint out = IERC20(RealLib.TOKEN_MORE).balanceOf(address(this));
        assertEq(out, 2566202052422617019965);
        deal(RealLib.TOKEN_USDC, address(adapter), 10000e6);
        vm.expectRevert(bytes("!PRICE 8173"));
        adapter.swap(RealLib.POOL_PEARL_MORE_USDC, RealLib.TOKEN_USDC, RealLib.TOKEN_MORE, address(this), 1_000);
    }
}
