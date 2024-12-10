// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SolidlyAdapter} from "../../src/adapters/SolidlyAdapter.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IHardWorker} from "../../src/interfaces/IHardWorker.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {RealLib} from "../../chains/RealLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract SolidlyAdapterTest is Test {
    address public constant PLATFORM = 0xB7838d447deece2a9A5794De0f342B47d0c1B9DC;
    IAmmAdapter public adapter;
    bytes32 public _hash;

    // address public constant STRATEGY = 0xe5984e388dE3a2745b1a6566baD0B88ECF6c5A9B;
    address public constant STRATEGY = 0xF85530577DCB8A00C2254a1C7885F847230C3097;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("REAL_RPC_URL")));
        vm.rollFork(1225288); // dec 1 2024
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

    function testViewMethods() public {
        _addAdapter();

        assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash);

        uint[] memory amounts = new uint[](2);
        amounts[0] = 10e18;
        amounts[1] = 10e6;
        (uint liquidity, uint[] memory amountsConsumed) =
            adapter.getLiquidityForAmounts(RealLib.POOL_PEARL_MORE_USDC, amounts);
        assertGt(liquidity, 0);
        assertGt(amountsConsumed[0], 0);
        assertGt(amountsConsumed[1], 0);
        amounts[1] = 500e6;
        adapter.getLiquidityForAmounts(RealLib.POOL_PEARL_MORE_USDC, amounts);
        amounts[1] = 1000;
        adapter.getLiquidityForAmounts(RealLib.POOL_PEARL_MORE_USDC, amounts);

        // 0.38 USDC for 1 MORE at this block
        uint price = adapter.getPrice(RealLib.POOL_PEARL_MORE_USDC, RealLib.TOKEN_MORE, RealLib.TOKEN_USDC, 1e18);
        assertGt(price, 200000);
        assertLt(price, 300000);

        // ~~ 74.1%/25.9%
        uint[] memory props = adapter.getProportions(RealLib.POOL_PEARL_MORE_USDC);
        assertGt(props[0], 74e16);
        assertLt(props[0], 75e16);

        adapter.poolTokens(RealLib.POOL_PEARL_MORE_USDC);

        assertEq(adapter.supportsInterface(type(IAmmAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IERC165).interfaceId), true);
    }

    function testSwaps() public {
        _addAdapter();

        deal(RealLib.TOKEN_USDC, address(adapter), 1000e6);
        adapter.swap(RealLib.POOL_PEARL_MORE_USDC, RealLib.TOKEN_USDC, RealLib.TOKEN_MORE, address(this), 10_000);
        uint out = IERC20(RealLib.TOKEN_MORE).balanceOf(address(this));
        assertEq(out, 4598483639477195634671);
        deal(RealLib.TOKEN_USDC, address(adapter), 10000e6);
        vm.expectRevert(bytes("!PRICE 49453"));
        adapter.swap(RealLib.POOL_PEARL_MORE_USDC, RealLib.TOKEN_USDC, RealLib.TOKEN_MORE, address(this), 10_000);
    }

    /*function testHardWorksWithAdapter() public {
        ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());
        IHardWorker hw = IHardWorker(IPlatform(PLATFORM).hardWorker());
        address multisig = IPlatform(PLATFORM).multisig();

        // setup swapper
        ISwapper.AddPoolData[] memory pools = new ISwapper.AddPoolData[](1);
        uint i;
        pools[i++] = _makePoolData(RealLib.POOL_PEARL_MORE_USDC, AmmAdapterIdLib.SOLIDLY, RealLib.TOKEN_MORE, RealLib.TOKEN_USDC);
    //  pools[i++] = _makePoolData(RealLib.POOL_PEARL_MORE_USTB_100, AmmAdapterIdLib.UNISWAPV3, RealLib.TOKEN_MORE, RealLib.TOKEN_USTB);
    //  pools[i++] = _makePoolData(RealLib.POOL_PEARL_DAI_USTB_100, AmmAdapterIdLib.UNISWAPV3, RealLib.TOKEN_USTB, RealLib.TOKEN_DAI);
    //  pools[i++] = _makePoolData(RealLib.POOL_PEARL_USTB_arcUSD_100, AmmAdapterIdLib.UNISWAPV3, RealLib.TOKEN_arcUSD, RealLib.TOKEN_USTB);
        vm.prank(multisig);
        swapper.addPools(pools, true);

        // also hardwork
        vm.prank(multisig);
        hw.setDedicatedServerMsgSender(address(this), true);
        address[] memory vaultsForHardWork = new address[](1);
        vaultsForHardWork[0] = IStrategy(STRATEGY).vault();
        hw.call(vaultsForHardWork);


    }*/

    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return ISwapper.AddPoolData({pool: pool, ammAdapterId: ammAdapterId, tokenIn: tokenIn, tokenOut: tokenOut});
    }
}
