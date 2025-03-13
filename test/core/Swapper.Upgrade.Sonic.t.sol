// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console, Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {Swapper} from "../../src/core/Swapper.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicLib} from "../../chains/SonicLib.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {BalancerV3StableAdapter} from "../../src/adapters/BalancerV3StableAdapter.sol";

contract SwapperUpgradeSonicTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    ISwapper public swapper;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(13119000); // Mar-11-2025 08:29:09 PM +UTC
        swapper = ISwapper(IPlatform(PLATFORM).swapper());
    }

    function testSwapperUpgrade() public {
        address multisig = IPlatform(PLATFORM).multisig();

        vm.startPrank(multisig);
        _upgrade();
        _addAdapter();
        swapper.addPools(_routes(), false);
        vm.stopPrank();

        uint price = swapper.getPrice(SonicLib.TOKEN_USDC, SonicLib.TOKEN_wanS, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicLib.TOKEN_wanS, SonicLib.TOKEN_USDC, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicLib.TOKEN_wstkscUSD, SonicLib.TOKEN_USDC, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicLib.TOKEN_USDC, SonicLib.TOKEN_wstkscUSD, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicLib.TOKEN_USDC, SonicLib.TOKEN_wstkscETH, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicLib.TOKEN_wstkscETH, SonicLib.TOKEN_USDC, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicLib.TOKEN_wETH, SonicLib.TOKEN_wstkscETH, 0);
        assertGt(price, 0);
        price = swapper.getPrice(SonicLib.TOKEN_wstkscETH, SonicLib.TOKEN_wETH, 0);
        assertGt(price, 0);
    }

    function _addAdapter() internal {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BalancerV3StableAdapter()));
        BalancerV3StableAdapter(address(proxy)).init(PLATFORM);
        BalancerV3StableAdapter(address(proxy)).setupHelpers(SonicLib.BEETS_V3_ROUTER);
        IPlatform(PLATFORM).addAmmAdapter(AmmAdapterIdLib.BALANCER_V3_STABLE, address(proxy));
    }

    function _upgrade() internal {
        address newImplementation = address(new Swapper());
        address[] memory proxies = new address[](1);
        proxies[0] = address(swapper);
        address[] memory implementations = new address[](1);
        implementations[0] = newImplementation;
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.03.0-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
    }

    function _routes() internal pure returns (ISwapper.AddPoolData[] memory pools) {
        pools = new ISwapper.AddPoolData[](7);
        uint i;
        // wanS -> USDC
        pools[i++] = _makePoolData(
            SonicLib.SILO_VAULT_25_wS, AmmAdapterIdLib.ERC_4626, SonicLib.SILO_VAULT_25_wS, SonicLib.TOKEN_wS
        );
        pools[i++] = _makePoolData(
            SonicLib.POOL_BEETS_V3_SILO_VAULT_25_wS_anS,
            AmmAdapterIdLib.BALANCER_V3_STABLE,
            SonicLib.TOKEN_anS,
            SonicLib.SILO_VAULT_25_wS
        );
        pools[i++] =
            _makePoolData(SonicLib.TOKEN_wanS, AmmAdapterIdLib.ERC_4626, SonicLib.TOKEN_wanS, SonicLib.TOKEN_anS);

        // wstkscUSD -> USDC
        pools[i++] = _makePoolData(
            SonicLib.TOKEN_wstkscUSD, AmmAdapterIdLib.ERC_4626, SonicLib.TOKEN_wstkscUSD, SonicLib.TOKEN_stkscUSD
        );
        pools[i++] = _makePoolData(
            SonicLib.POOL_SHADOW_CL_stkscUSD_scUSD_3000,
            AmmAdapterIdLib.UNISWAPV3,
            SonicLib.TOKEN_stkscUSD,
            SonicLib.TOKEN_scUSD
        );

        // wstksceth -> USDC
        pools[i++] = _makePoolData(
            SonicLib.TOKEN_wstkscETH, AmmAdapterIdLib.ERC_4626, SonicLib.TOKEN_wstkscETH, SonicLib.TOKEN_stkscETH
        );
        pools[i++] = _makePoolData(
            SonicLib.POOL_SHADOW_CL_scETH_stkscETH_250,
            AmmAdapterIdLib.UNISWAPV3,
            SonicLib.TOKEN_stkscETH,
            SonicLib.TOKEN_scETH
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
