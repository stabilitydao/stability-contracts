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

        uint price = swapper.getPrice(SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_wanS, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_wanS, SonicConstantsLib.TOKEN_USDC, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_wstkscUSD, SonicConstantsLib.TOKEN_USDC, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_wstkscUSD, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_wstkscETH, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_wstkscETH, SonicConstantsLib.TOKEN_USDC, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_wETH, SonicConstantsLib.TOKEN_wstkscETH, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_wstkscETH, SonicConstantsLib.TOKEN_wETH, 0);
        assertGt(price, 0);

        price = swapper.getPrice(SonicConstantsLib.TOKEN_sfrxUSD, SonicConstantsLib.TOKEN_SWPx, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_SWPx, SonicConstantsLib.TOKEN_sfrxUSD, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicConstantsLib.TOKEN_SWPx, SonicConstantsLib.TOKEN_frxUSD, 0);
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
            SonicConstantsLib.SILO_VAULT_25_wS,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.SILO_VAULT_25_wS,
            SonicConstantsLib.TOKEN_wS
        );
        pools[i++] = _makePoolData(
            SonicConstantsLib.POOL_BEETS_V3_SILO_VAULT_25_wS_anS,
            AmmAdapterIdLib.BALANCER_V3_STABLE,
            SonicConstantsLib.TOKEN_anS,
            SonicConstantsLib.SILO_VAULT_25_wS
        );
        pools[i++] = _makePoolData(
            SonicConstantsLib.TOKEN_wanS,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.TOKEN_wanS,
            SonicConstantsLib.TOKEN_anS
        );

        // wstkscUSD -> USDC
        pools[i++] = _makePoolData(
            SonicConstantsLib.TOKEN_wstkscUSD,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.TOKEN_stkscUSD,
            SonicConstantsLib.TOKEN_wstkscUSD
        );
        /*pools[i++] = _makePoolData(
            SonicConstantsLib.POOL_SHADOW_CL_stkscUSD_scUSD_3000,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.TOKEN_stkscUSD,
            SonicConstantsLib.TOKEN_scUSD
        );*/

        // wstksceth -> ETH
        pools[i++] = _makePoolData(
            SonicConstantsLib.TOKEN_wstkscETH,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.TOKEN_wstkscETH,
            SonicConstantsLib.TOKEN_stkscETH
        );
        pools[i++] = _makePoolData(
            SonicConstantsLib.POOL_SHADOW_CL_scETH_stkscETH_250,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.TOKEN_stkscETH,
            SonicConstantsLib.TOKEN_scETH
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
