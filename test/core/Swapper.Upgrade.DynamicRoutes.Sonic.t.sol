// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console, Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {Swapper} from "../../src/core/Swapper.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {BalancerV3StableAdapter} from "../../src/adapters/BalancerV3StableAdapter.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice #261, #330: exclude cycling routes, add dynamic routes
contract SwapperUpgradeDynamicRoutesSonicTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    ISwapper public swapper;
    address[2][20] public KNOWN_CYCLING_PAIRS;
    address[52] public tokens;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        // vm.rollFork(13624880); // Mar-14-2025 07:49:27 AM +UTC
        vm.rollFork(35952740); // Jun-26-2025 04:45:01 AM +UTC
        swapper = ISwapper(IPlatform(PLATFORM).swapper());

        KNOWN_CYCLING_PAIRS = [
            [SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_wstkscUSD],
            [SonicConstantsLib.TOKEN_wS, SonicConstantsLib.TOKEN_wETH],
            [SonicConstantsLib.TOKEN_scUSD, SonicConstantsLib.TOKEN_sfrxUSD],
            [SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_auUSDC],
            [SonicConstantsLib.TOKEN_wS, SonicConstantsLib.TOKEN_scUSD],
            [SonicConstantsLib.TOKEN_wS, SonicConstantsLib.TOKEN_wOS],
            [SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_PT_Silo_46_scUSD_14AUG2025],
            [SonicConstantsLib.TOKEN_wS, SonicConstantsLib.TOKEN_stkscETH],
            [SonicConstantsLib.TOKEN_wS, SonicConstantsLib.TOKEN_anS],
            [SonicConstantsLib.TOKEN_wETH, SonicConstantsLib.TOKEN_stkscETH],
            [SonicConstantsLib.TOKEN_wS, SonicConstantsLib.TOKEN_wanS],
            [SonicConstantsLib.TOKEN_wETH, SonicConstantsLib.TOKEN_atETH],
            [SonicConstantsLib.TOKEN_wS, SonicConstantsLib.TOKEN_PT_Silo_20_USDC_17JUL2025],
            [SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_scETH],
            [SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_frxUSD],
            [SonicConstantsLib.TOKEN_wS, SonicConstantsLib.TOKEN_SILO],
            [SonicConstantsLib.TOKEN_wS, SonicConstantsLib.TOKEN_frxUSD],
            [SonicConstantsLib.TOKEN_wS, SonicConstantsLib.TOKEN_bUSDCe20],
            [SonicConstantsLib.TOKEN_wS, SonicConstantsLib.TOKEN_aUSDC],
            [SonicConstantsLib.TOKEN_scETH, SonicConstantsLib.TOKEN_PT_wstkscETH_29MAY2025]
        ];

        tokens = [
            SonicConstantsLib.TOKEN_wS,
            SonicConstantsLib.TOKEN_wETH,
            SonicConstantsLib.TOKEN_wBTC,
            SonicConstantsLib.TOKEN_USDC, // 3
            SonicConstantsLib.TOKEN_stS,
            SonicConstantsLib.TOKEN_BEETS,
            SonicConstantsLib.TOKEN_EURC,
            SonicConstantsLib.TOKEN_EQUAL,
            SonicConstantsLib.TOKEN_scUSD, // 8
            SonicConstantsLib.TOKEN_GOGLZ,
            SonicConstantsLib.TOKEN_SACRA,
            SonicConstantsLib.TOKEN_SACRA_GEM_1,
            SonicConstantsLib.TOKEN_SWPx,
            SonicConstantsLib.TOKEN_scETH, // 13
            SonicConstantsLib.TOKEN_atETH, // 14
            SonicConstantsLib.TOKEN_AUR,
            SonicConstantsLib.TOKEN_auUSDC, // 16
            SonicConstantsLib.TOKEN_BRUSH,
            SonicConstantsLib.TOKEN_FS,
            SonicConstantsLib.TOKEN_sDOG,
            SonicConstantsLib.TOKEN_MOON,
            SonicConstantsLib.TOKEN_OS,
            SonicConstantsLib.TOKEN_SHADOW,
            SonicConstantsLib.TOKEN_xSHADOW,
            SonicConstantsLib.TOKEN_sGEM1,
            SonicConstantsLib.TOKEN_stkscUSD,
            SonicConstantsLib.TOKEN_wstkscUSD,
            SonicConstantsLib.TOKEN_stkscETH, // 27
            SonicConstantsLib.TOKEN_wstkscETH,
            SonicConstantsLib.TOKEN_wOS, // 29
            SonicConstantsLib.TOKEN_STBL,
            SonicConstantsLib.TOKEN_anS, // 31
            SonicConstantsLib.TOKEN_wanS, // 32
            SonicConstantsLib.TOKEN_frxUSD, // 33
            SonicConstantsLib.TOKEN_sfrxUSD, // 34
            SonicConstantsLib.TOKEN_x33,
            SonicConstantsLib.TOKEN_DIAMONDS,
            SonicConstantsLib.TOKEN_aUSDC, // 37
            SonicConstantsLib.TOKEN_PT_aUSDC_14AUG2025,
            SonicConstantsLib.TOKEN_PT_stS_29MAY2025,
            SonicConstantsLib.TOKEN_PT_wstkscUSD_29MAY2025,
            SonicConstantsLib.TOKEN_PT_wstkscETH_29MAY2025, // 41
            SonicConstantsLib.TOKEN_PT_wOS_29MAY2025,
            SonicConstantsLib.TOKEN_PT_Silo_46_scUSD_14AUG2025, // 43
            SonicConstantsLib.TOKEN_PT_Silo_20_USDC_17JUL2025, // 44
            SonicConstantsLib.TOKEN_GEMSx,
            SonicConstantsLib.TOKEN_bUSDCe20, // 46
            SonicConstantsLib.TOKEN_BeetsFragmentsS1,
            SonicConstantsLib.TOKEN_USDT,
            SonicConstantsLib.TOKEN_SILO, // 49
            SonicConstantsLib.TOKEN_beS,

            SonicConstantsLib.SILO_VAULT_25_wS
        ];
    }

    //region --------------------------------------- Cycling routes #261
    /// @notice #261: ensure that known single cycling route is not detected as cycling
    function testSingleCyclingRoutes() public {
        _upgrade();

        address tokenIn = KNOWN_CYCLING_PAIRS[0][0];
        address tokenOut = KNOWN_CYCLING_PAIRS[0][1];

        (ISwapper.PoolData[] memory route,) = swapper.buildRoute(tokenIn, tokenOut);
        // _displayRoute(route, 0, 0, tokenIn, tokenOut);
        assertEq(_isCycling(route), false);
    }

    /// @notice #261: ensure that known cycling routes are not detected as cycling
    function testCheckKnownCyclingRoutes() public {
        _upgrade();

        for (uint i = 0; i < KNOWN_CYCLING_PAIRS.length; i++) {
            address tokenIn = KNOWN_CYCLING_PAIRS[i][0];
            address tokenOut = KNOWN_CYCLING_PAIRS[i][1];

            (ISwapper.PoolData[] memory route,) = swapper.buildRoute(tokenIn, tokenOut);
            // _displayRoute(route, 0, 0, tokenIn, tokenOut);
            assertEq(_isCycling(route), false);
        }
    }
    //endregion --------------------------------------- Cycling routes #261

    //region --------------------------------------- Tests to find cycling routes #261

//    function testSearchProblemRoutes__Fuzzy(uint from, uint to) public view {

//        from = bound(from, 0, tokens.length - 1);
//        to = bound(to, 0, tokens.length - 1);
//        if (from == to) {
//            return; // no route
//        }
//
//        (ISwapper.PoolData[] memory route,) = swapper.buildRoute(tokens[from], tokens[to]);
//        if (route.length != 0) {
//            if (_isCycling(route) && !_isKnownCyclingPair(tokens[from], tokens[to])) {
//                _displayRoute(route, from, to, tokens[from], tokens[to]);
//                assertEq(false, true);
//            }
//        }
//    }
//
//    function testSearchProblemRoutesCycle(uint from, uint to) public view {
//        from = bound(from, 0, tokens.length - 1);
//        to = bound(to, 0, tokens.length - 1);
//        if (from == to) {
//            return; // no route
//        }
//
//        for (uint i = 0; i < tokens.length; ++i) {
//            for (uint j = i; j < tokens.length; ++j) {
//                (ISwapper.PoolData[] memory route,) = swapper.buildRoute(tokens[from], tokens[to]);
//                if (route.length != 0) {
//                    if (_isCycling(route) && !_isKnownCyclingPair(tokens[from], tokens[to])) {
//                        console.log("!!!!!!!!!!!Cycling route found for:", tokens[from], tokens[to]);
//                        _displayRoute(route, from, to, tokens[from], tokens[to]);
//                    }
//                }
//            }
//        }
//    }

    //endregion --------------------------------------- Tests to find cycling routes #261

    //region --------------------------------------- Internal logic
    function _displayRoute(ISwapper.PoolData[] memory route, uint from, uint to, address tokenIn, address tokenOut) internal view {
        console.log("Route:");
        console.log(from, to, tokenIn, tokenOut);
        console.log(IERC20Metadata(tokenIn).symbol(), IERC20Metadata(tokenOut).symbol());
        for (uint i = 0; i < route.length; i++) {
            console.log("i", i);
            console.log("pool", route[i].pool);
            console.log("ammAdapter", route[i].ammAdapter);
            console.log("tokenIn", route[i].tokenIn);
            console.log("tokenOut", route[i].tokenOut);
        }
    }

    function _isCycling(ISwapper.PoolData[] memory route) internal pure returns (bool) {
        address[] memory tokenIn = new address[](route.length);
        uint tokenInCount;
        address[] memory tokenOut = new address[](route.length);
        uint tokenOutCount;

        for (uint i = 0; i < route.length; i++) {
            for (uint j = 0; j < tokenInCount; j++) {
                if (route[i].tokenIn == tokenIn[j]) return true;
            }
            tokenIn[tokenInCount++] = route[i].tokenIn;

            for (uint j = 0; j < tokenOutCount; j++) {
                if (route[i].tokenOut == tokenOut[j]) return true;
            }
            tokenOut[tokenOutCount++] = route[i].tokenOut;
        }

        return false;
    }

    function _isKnownCyclingPair(
        address tokenIn,
        address tokenOut
    ) internal view returns (bool) {
        for (uint i = 0; i < KNOWN_CYCLING_PAIRS.length; i++) {
            if (
                (KNOWN_CYCLING_PAIRS[i][0] == tokenIn && KNOWN_CYCLING_PAIRS[i][1] == tokenOut) ||
                (KNOWN_CYCLING_PAIRS[i][0] == tokenOut && KNOWN_CYCLING_PAIRS[i][1] == tokenIn)
            ) {
                return true;
            }
        }
        return false;
    }

    //endregion --------------------------------------- Internal logic

    //region --------------------------------------- Helper functions
    function _addAdapter() internal {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BalancerV3StableAdapter()));
        BalancerV3StableAdapter(address(proxy)).init(PLATFORM);
        BalancerV3StableAdapter(address(proxy)).setupHelpers(SonicConstantsLib.BEETS_V3_ROUTER);
        IPlatform(PLATFORM).addAmmAdapter(AmmAdapterIdLib.BALANCER_V3_STABLE, address(proxy));
    }

    function _upgrade() internal {
        address multisig = IPlatform(PLATFORM).multisig();

        address newImplementation = address(new Swapper());
        address[] memory proxies = new address[](1);
        proxies[0] = address(swapper);
        address[] memory implementations = new address[](1);
        implementations[0] = newImplementation;

        vm.prank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.03.1-alpha", proxies, implementations);

        skip(1 days);

        vm.prank(multisig);
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
    //endregion --------------------------------------- Helper functions
}
