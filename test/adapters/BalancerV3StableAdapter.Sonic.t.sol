// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {SonicConstantsLib, AmmAdapterIdLib, IBalancerAdapter} from "../../chains/sonic/SonicLib.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";

contract BalancerV3StableAdapterTest is SonicSetup {
    bytes32 public _hash;
    IAmmAdapter public adapter;

    constructor() {
        // vm.rollFork(13624880); // Mar-14-2025 08:29:09 PM +UTC
        _init();
        _hash = keccak256(bytes(AmmAdapterIdLib.BALANCER_V3_STABLE));
        adapter = IAmmAdapter(platform.ammAdapter(_hash).proxy);
        //console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.BalancerV3StableAdapter")) - 1)) & ~bytes32(uint256(0xff)));
    }

    function testIBalancerAdapter() public {
        IBalancerAdapter balancerAdapter = IBalancerAdapter(address(adapter));
        vm.expectRevert(IControllable.AlreadyExist.selector);
        balancerAdapter.setupHelpers(address(1));

        address pool = SonicConstantsLib.POOL_BEETS_V3_SILO_VAULT_25_WS_ANS;
        uint[] memory amounts = new uint[](2);
        amounts[0] = 1e15;
        amounts[1] = 100e18;
        vm.startPrank(address(0), address(0));
        (uint liquidity, uint[] memory amountsConsumed) = balancerAdapter.getLiquidityForAmountsWrite(pool, amounts);
        vm.stopPrank();
        assertGt(liquidity, 1e10);
        assertEq(amountsConsumed[0], amounts[0]);
        assertEq(amountsConsumed[1], amounts[1]);
        //console.log(liquidity);
        //console.log(amountsConsumed[0]);
        //console.log(amountsConsumed[1]);
    }

    function testSwaps() public {
        address pool = SonicConstantsLib.POOL_BEETS_V3_SILO_VAULT_25_WS_ANS;
        deal(SonicConstantsLib.SILO_VAULT_25_WS, address(adapter), 1e15);
        adapter.swap(pool, SonicConstantsLib.SILO_VAULT_25_WS, SonicConstantsLib.TOKEN_ANS, address(this), 10_000);
        uint out = IERC20(SonicConstantsLib.TOKEN_ANS).balanceOf(address(this));
        assertGt(out, 0);
        // console.log(out);
        deal(SonicConstantsLib.SILO_VAULT_25_WS, address(adapter), 200000000e18);
        vm.expectRevert();
        adapter.swap(pool, SonicConstantsLib.SILO_VAULT_25_WS, SonicConstantsLib.TOKEN_ANS, address(this), 1);
        // out = IERC20(SonicConstantsLib.TOKEN_STS).balanceOf(address(this));
        // console.log(out);
    }

    function testViewMethods() public view {
        assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash);

        address pool = SonicConstantsLib.POOL_BEETS_V3_SILO_VAULT_25_WS_ANS;
        address[] memory tokens = adapter.poolTokens(pool);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], SonicConstantsLib.SILO_VAULT_25_WS);
        assertEq(tokens[1], SonicConstantsLib.TOKEN_ANS);

        uint[] memory props = adapter.getProportions(pool);
        assertLt(props[0], 4e17);
        assertGt(props[1], 4e17);
        //console.log(props[0]);
        //console.log(props[1]);

        uint price;
        price = adapter.getPrice(pool, SonicConstantsLib.SILO_VAULT_25_WS, SonicConstantsLib.TOKEN_ANS, 1e18);
        assertGt(price, 9e14);
        assertLt(price, 11e14);
        //console.log(price);
        // 1000669414155242

        assertEq(adapter.supportsInterface(type(IAmmAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IBalancerAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IERC165).interfaceId), true);
    }

    function testGetTwaPrice() public {
        vm.expectRevert("Not supported");
        adapter.getTwaPrice(address(0), address(0), address(0), 0, 0);
    }
}
