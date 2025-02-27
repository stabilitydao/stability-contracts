// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test, console} from "forge-std/Test.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {ERC4626Adapter} from "../../src/adapters/ERC4626Adapter.sol";
import {SonicLib} from "../../chains/SonicLib.sol";

contract ERC4626AdapterTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    bytes32 public _hash;
    IAmmAdapter public adapter;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(10332000); // Feb-26-2025 04:14:04 PM +UTC
    }

    function _addAdapter() internal {
        _hash = keccak256(bytes(AmmAdapterIdLib.ERC_4626));
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new ERC4626Adapter()));
        adapter = IAmmAdapter(address(proxy));
        adapter.init(PLATFORM);
        string memory id = AmmAdapterIdLib.ERC_4626;
        vm.prank(IPlatform(PLATFORM).multisig());
        IPlatform(PLATFORM).addAmmAdapter(id, address(proxy));
    }

    function testSwaps() public {
        _addAdapter();
        ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());
        address multisig = IPlatform(PLATFORM).multisig();

        // setup swapper
        ISwapper.AddPoolData[] memory bcPools = new ISwapper.AddPoolData[](2);
        bcPools[0] = _makePoolData(
            SonicLib.POOL_SHADOW_CL_USDC_scUSD_100, AmmAdapterIdLib.UNISWAPV3, SonicLib.TOKEN_scUSD, SonicLib.TOKEN_USDC
        );
        bcPools[1] = _makePoolData(
            SonicLib.POOL_SHADOW_CL_scETH_WETH_100, AmmAdapterIdLib.UNISWAPV3, SonicLib.TOKEN_scETH, SonicLib.TOKEN_wETH
        );

        ISwapper.AddPoolData[] memory pools = new ISwapper.AddPoolData[](4);
        pools[0] = _makePoolData(
            SonicLib.TOKEN_wstkscUSD, AmmAdapterIdLib.ERC_4626, SonicLib.TOKEN_wstkscUSD, SonicLib.TOKEN_stkscUSD
        );
        pools[1] = _makePoolData(
            SonicLib.POOL_SHADOW_CL_stkscUSD_scUSD_3000,
            AmmAdapterIdLib.UNISWAPV3,
            SonicLib.TOKEN_stkscUSD,
            SonicLib.TOKEN_scUSD
        );
        pools[2] = _makePoolData(
            SonicLib.TOKEN_wstkscETH, AmmAdapterIdLib.ERC_4626, SonicLib.TOKEN_wstkscETH, SonicLib.TOKEN_stkscETH
        );
        pools[3] = _makePoolData(
            SonicLib.POOL_SHADOW_CL_scETH_stkscETH_250,
            AmmAdapterIdLib.UNISWAPV3,
            SonicLib.TOKEN_stkscETH,
            SonicLib.TOKEN_scETH
        );

        vm.startPrank(multisig);
        swapper.addBlueChipsPools(bcPools, false);
        swapper.addPools(pools, false);
        vm.stopPrank();

        deal(SonicLib.TOKEN_USDC, address(this), 1000e6);
        IERC20(SonicLib.TOKEN_USDC).approve(address(swapper), type(uint).max);
        IERC20(SonicLib.TOKEN_wstkscUSD).approve(address(swapper), type(uint).max);
        swapper.swap(SonicLib.TOKEN_USDC, SonicLib.TOKEN_wstkscUSD, 1000e6, 100);
        swapper.swap(
            SonicLib.TOKEN_wstkscUSD,
            SonicLib.TOKEN_USDC,
            IERC20(SonicLib.TOKEN_wstkscUSD).balanceOf(address(this)),
            100
        );

        deal(SonicLib.TOKEN_wETH, address(this), 10e18);
        IERC20(SonicLib.TOKEN_wETH).approve(address(swapper), type(uint).max);
        IERC20(SonicLib.TOKEN_wstkscETH).approve(address(swapper), type(uint).max);
        swapper.swap(SonicLib.TOKEN_wETH, SonicLib.TOKEN_wstkscETH, 10e18, 300);
        swapper.swap(
            SonicLib.TOKEN_wstkscETH,
            SonicLib.TOKEN_wETH,
            IERC20(SonicLib.TOKEN_wstkscETH).balanceOf(address(this)),
            300
        );
    }

    function testViewMethods() public {
        _addAdapter();

        assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash);
        assertEq(adapter.getPrice(SonicLib.TOKEN_wstkscUSD, SonicLib.TOKEN_wstkscUSD, address(0), 1e6), 1e6);

        // change price
        deal(SonicLib.TOKEN_stkscUSD, address(this), 10000e6);
        IERC20(SonicLib.TOKEN_stkscUSD).transfer(SonicLib.TOKEN_wstkscUSD, 10000e6);
        assertEq(adapter.getPrice(SonicLib.TOKEN_wstkscUSD, SonicLib.TOKEN_wstkscUSD, address(0), 1e6), 1001624);
        assertEq(adapter.getPrice(SonicLib.TOKEN_wstkscUSD, SonicLib.TOKEN_stkscUSD, address(0), 1e6), 998377);

        //console.log(adapter.getPrice(SonicLib.TOKEN_wstkscUSD, SonicLib.TOKEN_stkscUSD, address(0), 1e6));

        vm.expectRevert("Not supported");
        adapter.getLiquidityForAmounts(address(0), new uint[](2));

        vm.expectRevert("Not supported");
        adapter.getProportions(address(0));

        adapter.poolTokens(SonicLib.TOKEN_wstkscUSD);

        assertEq(adapter.supportsInterface(type(IAmmAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IERC165).interfaceId), true);
    }

    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return ISwapper.AddPoolData({pool: pool, ammAdapterId: ammAdapterId, tokenIn: tokenIn, tokenOut: tokenOut});
    }
}
