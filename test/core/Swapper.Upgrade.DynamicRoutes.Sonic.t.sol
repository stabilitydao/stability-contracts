// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../src/adapters/MetaUsdAdapter.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {BalancerV3StableAdapter} from "../../src/adapters/BalancerV3StableAdapter.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Swapper} from "../../src/core/Swapper.sol";
import {console, Test} from "forge-std/Test.sol";

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
    //region --------------------------------------- Dynamic routes
    function testSwapMetaUsd() public {
        _upgrade();
        _addAdapter();
        _routes();

        assertEq(IERC20(SonicConstantsLib.METAVAULT_metaUSD).balanceOf(address(this)), 0);

        deal(SonicConstantsLib.TOKEN_USDC, address(this), 1e18);
        IERC20(SonicConstantsLib.TOKEN_USDC).approve(address(swapper), type(uint).max);

        //--------------------------------- USDC => metaUSD
        console.log("!!!!!!!!!!!!!!!!!USDC => metaUSD");
        swapper.swap(SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.METAVAULT_metaUSD, 1e18, 1);
        uint balanceMetaUsd0 = IERC20(SonicConstantsLib.METAVAULT_metaUSD).balanceOf(address(this));
        uint balanceUsdc0 = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this));

        assertNotEq(balanceMetaUsd0, 0);
        assertEq(balanceUsdc0, 0);

        //--------------------------------- metaUSD => USDC
        console.log("!!!!!!!!!!!!!!!!!metaUSD => USDC");
        IERC20(SonicConstantsLib.METAVAULT_metaUSD).approve(address(swapper), type(uint).max);
        swapper.swap(SonicConstantsLib.METAVAULT_metaUSD, SonicConstantsLib.TOKEN_USDC, balanceMetaUsd0, 1);

        uint balanceMetaUsd1 = IERC20(SonicConstantsLib.METAVAULT_metaUSD).balanceOf(address(this));
        uint balanceUsdc1 = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this));

        assertEq(balanceMetaUsd1, 0);
        assertEq(balanceUsdc1, 1e18);
    }


    //endregion --------------------------------------- Dynamic routes

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
        address multisig = IPlatform(PLATFORM).multisig();
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new MetaUsdAdapter()));
        MetaUsdAdapter(address(proxy)).init(PLATFORM);

        vm.prank(multisig);
        IPlatform(PLATFORM).addAmmAdapter(AmmAdapterIdLib.META_USD, address(proxy));
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
            SonicConstantsLib.METAVAULT_metaUSD,
            AmmAdapterIdLib.META_USD,
            SonicConstantsLib.METAVAULT_metaUSD,
            SonicConstantsLib.METAVAULT_metaUSD
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
