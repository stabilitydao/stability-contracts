// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {PlasmaConstantsLib, AmmAdapterIdLib, IBalancerAdapter} from "../../chains/plasma/PlasmaLib.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {PlasmaSetup} from "../base/chains/PlasmaSetup.sol";

contract BalancerV3ReCLAMMAdapterTest is PlasmaSetup {
    /// @notice Expected proportions of tokens in the pool
    /// https://balancer.fi/pools/plasma/v3/0xe14ba497a7c51f34896d327ec075f3f18210a270
    /// For block FORK_BLOCK = 2196726 proportions on UI are following: WXPL 18.76%, USDT0 81.24%
    uint internal constant POOL_BALANCER_V3_RECLAMM_WXPL_USDT0_PROP0_MAX = 2e17;
    uint internal constant POOL_BALANCER_V3_RECLAMM_WXPL_USDT0_PROP1_MIN = 8e17;

    /// @notice Approximate price of WXPL in USD on the block FORK_BLOCK = 2196726
    /// @dev https://dexscreener.com/plasma/0x8603c67b7cc056ef6981a9c709854c53b699fa66
    uint internal constant PRICE_WXPL_USD_APPROX = 1.32e6;

    bytes32 public _hash;
    IAmmAdapter public adapter;

    constructor() {
        _init();
        _hash = keccak256(bytes(AmmAdapterIdLib.BALANCER_V3_RECLAMM));
        adapter = IAmmAdapter(platform.ammAdapter(_hash).proxy);
        //console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.BalancerV3ReClammAdapter")) - 1)) & ~bytes32(uint256(0xff)));
    }

    function testIBalancerAdapter() public {
        IBalancerAdapter balancerAdapter = IBalancerAdapter(address(adapter));
        vm.expectRevert(IControllable.AlreadyExist.selector);
        balancerAdapter.setupHelpers(address(1));

        address pool = PlasmaConstantsLib.POOL_BALANCER_V3_RECLAMM_WXPL_USDT0;
        uint[] memory amounts = new uint[](2);
        amounts[0] = 100e18;
        amounts[1] = 100e6;

        vm.expectRevert("Unavailable");
        balancerAdapter.getLiquidityForAmountsWrite(pool, amounts);

        vm.expectRevert("Unavailable");
        IAmmAdapter(address(balancerAdapter)).getLiquidityForAmounts(pool, amounts);
    }

    function testSwaps() public {
        address pool = PlasmaConstantsLib.POOL_BALANCER_V3_RECLAMM_WXPL_USDT0;

        // --------------------- Swap WXPL => USDT0 (tiny amount)
        {
            assertEq(IERC20(PlasmaConstantsLib.TOKEN_USDT0).balanceOf(address(this)), 0);
            deal(PlasmaConstantsLib.TOKEN_WXPL, address(adapter), 1e16);
            adapter.swap(pool, PlasmaConstantsLib.TOKEN_WXPL, PlasmaConstantsLib.TOKEN_USDT0, address(this), 10_000);
            uint out = IERC20(PlasmaConstantsLib.TOKEN_USDT0).balanceOf(address(this));
            assertGt(out, 0, "expected some USDT0 out");
        }

        // --------------------- Swap WXPL => USDT0 (1 decimal)
        {
            uint balance0 = IERC20(PlasmaConstantsLib.TOKEN_USDT0).balanceOf(address(this));
            deal(PlasmaConstantsLib.TOKEN_WXPL, address(adapter), 1e18);
            adapter.swap(pool, PlasmaConstantsLib.TOKEN_WXPL, PlasmaConstantsLib.TOKEN_USDT0, address(this), 10_000);
            uint out = IERC20(PlasmaConstantsLib.TOKEN_USDT0).balanceOf(address(this));
            assertApproxEqAbs(out - balance0, PRICE_WXPL_USD_APPROX / 100, PRICE_WXPL_USD_APPROX, "expected USDT0 2");
        }

        // --------------------- Swap USDT0 => WXPL
        {
            assertEq(IERC20(PlasmaConstantsLib.TOKEN_WXPL).balanceOf(address(this)), 0);
            deal(PlasmaConstantsLib.TOKEN_USDT0, address(adapter), PRICE_WXPL_USD_APPROX);
            adapter.swap(pool, PlasmaConstantsLib.TOKEN_USDT0, PlasmaConstantsLib.TOKEN_WXPL, address(this), 10_000);
            uint out = IERC20(PlasmaConstantsLib.TOKEN_WXPL).balanceOf(address(this));
            assertApproxEqAbs(out, 1e18, 1e18 / 100, "expected WXPL out");
        }

        // --------------------- Try to swap too low amount
        {
            deal(PlasmaConstantsLib.TOKEN_WXPL, address(adapter), 100);
            vm.expectRevert(IAmmAdapter.TooLowAmountIn.selector);
            adapter.swap(pool, PlasmaConstantsLib.TOKEN_WXPL, PlasmaConstantsLib.TOKEN_USDT0, address(this), 10_000);

            deal(PlasmaConstantsLib.TOKEN_WXPL, address(adapter), 1e10);
            vm.expectRevert(IAmmAdapter.TooLowAmountIn.selector);
            adapter.swap(pool, PlasmaConstantsLib.TOKEN_WXPL, PlasmaConstantsLib.TOKEN_USDT0, address(this), 10_000);

            deal(PlasmaConstantsLib.TOKEN_USDT0, address(adapter), 1e2);
            vm.expectRevert(IAmmAdapter.TooLowAmountIn.selector);
            adapter.swap(pool, PlasmaConstantsLib.TOKEN_USDT0, PlasmaConstantsLib.TOKEN_WXPL, address(this), 10_000);
        }

        // --------------------- Revert if price impact is too high
        deal(PlasmaConstantsLib.TOKEN_WXPL, address(adapter), 6e23);
        vm.expectRevert(); // !PRICE 10055
        adapter.swap(pool, PlasmaConstantsLib.TOKEN_WXPL, PlasmaConstantsLib.TOKEN_USDT0, address(this), 1);
    }

    function testViewMethods() public view {
        assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash);

        address pool = PlasmaConstantsLib.POOL_BALANCER_V3_RECLAMM_WXPL_USDT0;

        {
            address[] memory tokens = adapter.poolTokens(pool);
            assertEq(tokens.length, 2);
            assertEq(tokens[0], PlasmaConstantsLib.TOKEN_WXPL);
            assertEq(tokens[1], PlasmaConstantsLib.TOKEN_USDT0);
        }

        {
            uint[] memory props = adapter.getProportions(pool);
            assertLt(props[0], POOL_BALANCER_V3_RECLAMM_WXPL_USDT0_PROP0_MAX, "expected prop0");
            assertGt(props[1], POOL_BALANCER_V3_RECLAMM_WXPL_USDT0_PROP1_MIN, "expected prop1");
        }

        {
            uint price = adapter.getPrice(pool, PlasmaConstantsLib.TOKEN_WXPL, PlasmaConstantsLib.TOKEN_USDT0, 1e18);
            assertApproxEqAbs(
                price, PRICE_WXPL_USD_APPROX / 100, PRICE_WXPL_USD_APPROX, "expected price of WXPL in USDT0"
            );
        }

        {
            uint price = adapter.getPrice(pool, PlasmaConstantsLib.TOKEN_USDT0, PlasmaConstantsLib.TOKEN_WXPL, 1e6);
            uint expectedPrice = 1e18 * 1e6 / PRICE_WXPL_USD_APPROX;
            assertApproxEqAbs(price, expectedPrice / 100, expectedPrice, "expected price of USDT0 in WXPL");
        }

        assertEq(adapter.supportsInterface(type(IAmmAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IBalancerAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IERC165).interfaceId), true);
    }

    function testGetTwaPrice() public {
        vm.expectRevert("Not supported");
        adapter.getTwaPrice(address(0), address(0), address(0), 0, 0);
    }
}
