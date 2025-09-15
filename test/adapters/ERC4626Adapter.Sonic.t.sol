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
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";

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
            SonicConstantsLib.POOL_SHADOW_CL_USDC_SCUSD_100,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.TOKEN_SCUSD,
            SonicConstantsLib.TOKEN_USDC
        );
        bcPools[1] = _makePoolData(
            SonicConstantsLib.POOL_SHADOW_CL_SCETH_WETH_100,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.TOKEN_SCETH,
            SonicConstantsLib.TOKEN_WETH
        );

        ISwapper.AddPoolData[] memory pools = new ISwapper.AddPoolData[](4);
        pools[0] = _makePoolData(
            SonicConstantsLib.TOKEN_WSTKSCUSD,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.TOKEN_WSTKSCUSD,
            SonicConstantsLib.TOKEN_STKSCUSD
        );
        pools[1] = _makePoolData(
            SonicConstantsLib.POOL_SHADOW_CL_STKSCUSD_SCUSD_3000,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.TOKEN_STKSCUSD,
            SonicConstantsLib.TOKEN_SCUSD
        );
        pools[2] = _makePoolData(
            SonicConstantsLib.TOKEN_WSTKSCETH,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.TOKEN_WSTKSCETH,
            SonicConstantsLib.TOKEN_STKSCETH
        );
        pools[3] = _makePoolData(
            SonicConstantsLib.POOL_SHADOW_CL_SCETH_STKSCETH_250,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.TOKEN_STKSCETH,
            SonicConstantsLib.TOKEN_SCETH
        );

        vm.startPrank(multisig);
        swapper.addBlueChipsPools(bcPools, false);
        swapper.addPools(pools, false);
        vm.stopPrank();

        deal(SonicConstantsLib.TOKEN_USDC, address(this), 1000e6);
        IERC20(SonicConstantsLib.TOKEN_USDC).approve(address(swapper), type(uint).max);
        IERC20(SonicConstantsLib.TOKEN_WSTKSCUSD).approve(address(swapper), type(uint).max);
        swapper.swap(SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_WSTKSCUSD, 1000e6, 100);
        swapper.swap(
            SonicConstantsLib.TOKEN_WSTKSCUSD,
            SonicConstantsLib.TOKEN_USDC,
            IERC20(SonicConstantsLib.TOKEN_WSTKSCUSD).balanceOf(address(this)),
            100
        );

        deal(SonicConstantsLib.TOKEN_WETH, address(this), 10e18);
        IERC20(SonicConstantsLib.TOKEN_WETH).approve(address(swapper), type(uint).max);
        IERC20(SonicConstantsLib.TOKEN_WSTKSCETH).approve(address(swapper), type(uint).max);
        swapper.swap(SonicConstantsLib.TOKEN_WETH, SonicConstantsLib.TOKEN_WSTKSCETH, 10e18, 300);
        swapper.swap(
            SonicConstantsLib.TOKEN_WSTKSCETH,
            SonicConstantsLib.TOKEN_WETH,
            IERC20(SonicConstantsLib.TOKEN_WSTKSCETH).balanceOf(address(this)),
            300
        );
    }

    function testViewMethods() public {
        _addAdapter();

        assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash);
        assertEq(
            adapter.getPrice(SonicConstantsLib.TOKEN_WSTKSCUSD, SonicConstantsLib.TOKEN_WSTKSCUSD, address(0), 1e6), 1e6
        );

        // change price
        deal(SonicConstantsLib.TOKEN_STKSCUSD, address(this), 10000e6);
        IERC20(SonicConstantsLib.TOKEN_STKSCUSD).transfer(SonicConstantsLib.TOKEN_WSTKSCUSD, 10000e6);
        assertEq(
            adapter.getPrice(SonicConstantsLib.TOKEN_WSTKSCUSD, SonicConstantsLib.TOKEN_WSTKSCUSD, address(0), 1e6),
            1001624
        );
        assertEq(
            adapter.getPrice(SonicConstantsLib.TOKEN_WSTKSCUSD, SonicConstantsLib.TOKEN_STKSCUSD, address(0), 1e6),
            998377
        );

        //console.log(adapter.getPrice(SonicConstantsLib.TOKEN_WSTKSCUSD, SonicConstantsLib.TOKEN_STKSCUSD, address(0), 1e6));

        vm.expectRevert("Not supported");
        adapter.getLiquidityForAmounts(address(0), new uint[](2));

        vm.expectRevert("Not supported");
        adapter.getProportions(address(0));

        adapter.poolTokens(SonicConstantsLib.TOKEN_WSTKSCUSD);

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
