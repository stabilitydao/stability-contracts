// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {Swapper} from "../../src/core/Swapper.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {BalancerV3StableAdapter} from "../../src/adapters/BalancerV3StableAdapter.sol";

contract SwapperUpgradeSonicTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    ISwapper public swapper;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(13624880); // Mar-14-2025 07:49:27 AM +UTC
        swapper = ISwapper(IPlatform(PLATFORM).swapper());
    }

    function testSwapperUpgrade() public {
        address multisig = IPlatform(PLATFORM).multisig();

        vm.startPrank(multisig);
        _upgrade();
        _addAdapter();
        swapper.addPools(_routes(), false);
        vm.stopPrank();

        uint price = swapper.getPrice(SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_WANS, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_WANS, SonicConstantsLib.TOKEN_USDC, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_WSTKSCUSD, SonicConstantsLib.TOKEN_USDC, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_WSTKSCUSD, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_WSTKSCETH, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_WSTKSCETH, SonicConstantsLib.TOKEN_USDC, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_WETH, SonicConstantsLib.TOKEN_WSTKSCETH, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_WSTKSCETH, SonicConstantsLib.TOKEN_WETH, 0);
        assertGt(price, 0);

        price = swapper.getPrice(SonicConstantsLib.TOKEN_SFRXUSD, SonicConstantsLib.TOKEN_SWPX, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_SWPX, SonicConstantsLib.TOKEN_SFRXUSD, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_SWPX, SonicConstantsLib.TOKEN_FRXUSD, 0);
        assertGt(price, 0);
    }

    function _addAdapter() internal {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BalancerV3StableAdapter()));
        BalancerV3StableAdapter(address(proxy)).init(PLATFORM);
        BalancerV3StableAdapter(address(proxy)).setupHelpers(SonicConstantsLib.BEETS_V3_ROUTER);
        IPlatform(PLATFORM).addAmmAdapter(AmmAdapterIdLib.BALANCER_V3_STABLE, address(proxy));
    }

    function _upgrade() internal {
        address newImplementation = address(new Swapper());
        address[] memory proxies = new address[](1);
        proxies[0] = address(swapper);
        address[] memory implementations = new address[](1);
        implementations[0] = newImplementation;
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.03.1-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
    }

    function _routes() internal pure returns (ISwapper.AddPoolData[] memory pools) {
        pools = new ISwapper.AddPoolData[](6);
        uint i;
        // wanS -> USDC
        pools[i++] = _makePoolData(
            SonicConstantsLib.SILO_VAULT_25_WS,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.SILO_VAULT_25_WS,
            SonicConstantsLib.TOKEN_WS
        );
        pools[i++] = _makePoolData(
            SonicConstantsLib.POOL_BEETS_V3_SILO_VAULT_25_WS_ANS,
            AmmAdapterIdLib.BALANCER_V3_STABLE,
            SonicConstantsLib.TOKEN_ANS,
            SonicConstantsLib.SILO_VAULT_25_WS
        );
        pools[i++] = _makePoolData(
            SonicConstantsLib.TOKEN_WANS,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.TOKEN_WANS,
            SonicConstantsLib.TOKEN_ANS
        );

        // wstkscUSD -> USDC
        pools[i++] = _makePoolData(
            SonicConstantsLib.TOKEN_WSTKSCUSD,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.TOKEN_STKSCUSD,
            SonicConstantsLib.TOKEN_WSTKSCUSD
        );
        /*pools[i++] = _makePoolData(
            SonicConstantsLib.POOL_SHADOW_CL_STKSCUSD_SCUSD_3000,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.TOKEN_STKSCUSD,
            SonicConstantsLib.TOKEN_SCUSD
        );*/

        // wstksceth -> ETH
        pools[i++] = _makePoolData(
            SonicConstantsLib.TOKEN_WSTKSCETH,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.TOKEN_WSTKSCETH,
            SonicConstantsLib.TOKEN_STKSCETH
        );
        pools[i++] = _makePoolData(
            SonicConstantsLib.POOL_SHADOW_CL_SCETH_STKSCETH_250,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.TOKEN_STKSCETH,
            SonicConstantsLib.TOKEN_SCETH
        );
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
