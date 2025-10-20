// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MetaVaultAdapter} from "../../src/adapters/MetaVaultAdapter.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IStabilityVault} from "../../src/interfaces/IMetaVault.sol";
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
            [SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_WSTKSCUSD],
            [SonicConstantsLib.TOKEN_WS, SonicConstantsLib.TOKEN_WETH],
            [SonicConstantsLib.TOKEN_SCUSD, SonicConstantsLib.TOKEN_SFRXUSD],
            [SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_AUUSDC],
            [SonicConstantsLib.TOKEN_WS, SonicConstantsLib.TOKEN_SCUSD],
            [SonicConstantsLib.TOKEN_WS, SonicConstantsLib.TOKEN_WOS],
            [SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_PT_SILO_46_SCUSD_14AUG2025],
            [SonicConstantsLib.TOKEN_WS, SonicConstantsLib.TOKEN_STKSCETH],
            [SonicConstantsLib.TOKEN_WS, SonicConstantsLib.TOKEN_ANS],
            [SonicConstantsLib.TOKEN_WETH, SonicConstantsLib.TOKEN_STKSCETH],
            [SonicConstantsLib.TOKEN_WS, SonicConstantsLib.TOKEN_WANS],
            [SonicConstantsLib.TOKEN_WETH, SonicConstantsLib.TOKEN_ATETH],
            [SonicConstantsLib.TOKEN_WS, SonicConstantsLib.TOKEN_PT_SILO_20_USDC_17JUL2025],
            [SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_SCETH],
            [SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_FRXUSD],
            [SonicConstantsLib.TOKEN_WS, SonicConstantsLib.TOKEN_SILO],
            [SonicConstantsLib.TOKEN_WS, SonicConstantsLib.TOKEN_FRXUSD],
            [SonicConstantsLib.TOKEN_WS, SonicConstantsLib.TOKEN_BUSDCE20],
            [SonicConstantsLib.TOKEN_WS, SonicConstantsLib.TOKEN_AUSDC],
            [SonicConstantsLib.TOKEN_SCETH, SonicConstantsLib.TOKEN_PT_WSTKSCETH_29MAY2025]
        ];

        tokens = [
            SonicConstantsLib.TOKEN_WS,
            SonicConstantsLib.TOKEN_WETH,
            SonicConstantsLib.TOKEN_WBTC,
            SonicConstantsLib.TOKEN_USDC, // 3
            SonicConstantsLib.TOKEN_STS,
            SonicConstantsLib.TOKEN_BEETS,
            SonicConstantsLib.TOKEN_EURC,
            SonicConstantsLib.TOKEN_EQUAL,
            SonicConstantsLib.TOKEN_SCUSD, // 8
            SonicConstantsLib.TOKEN_GOGLZ,
            SonicConstantsLib.TOKEN_SACRA,
            SonicConstantsLib.TOKEN_SACRA_GEM_1,
            SonicConstantsLib.TOKEN_SWPX,
            SonicConstantsLib.TOKEN_SCETH, // 13
            SonicConstantsLib.TOKEN_ATETH, // 14
            SonicConstantsLib.TOKEN_AUR,
            SonicConstantsLib.TOKEN_AUUSDC, // 16
            SonicConstantsLib.TOKEN_BRUSH,
            SonicConstantsLib.TOKEN_FS,
            SonicConstantsLib.TOKEN_SDOG,
            SonicConstantsLib.TOKEN_MOON,
            SonicConstantsLib.TOKEN_OS,
            SonicConstantsLib.TOKEN_SHADOW,
            SonicConstantsLib.TOKEN_XSHADOW,
            SonicConstantsLib.TOKEN_SGEM1,
            SonicConstantsLib.TOKEN_STKSCUSD,
            SonicConstantsLib.TOKEN_WSTKSCUSD,
            SonicConstantsLib.TOKEN_STKSCETH, // 27
            SonicConstantsLib.TOKEN_WSTKSCETH,
            SonicConstantsLib.TOKEN_WOS, // 29
            SonicConstantsLib.TOKEN_STBL,
            SonicConstantsLib.TOKEN_ANS, // 31
            SonicConstantsLib.TOKEN_WANS, // 32
            SonicConstantsLib.TOKEN_FRXUSD, // 33
            SonicConstantsLib.TOKEN_SFRXUSD, // 34
            SonicConstantsLib.TOKEN_X33,
            SonicConstantsLib.TOKEN_DIAMONDS,
            SonicConstantsLib.TOKEN_AUSDC, // 37
            SonicConstantsLib.TOKEN_PT_AUSDC_14AUG2025,
            SonicConstantsLib.TOKEN_PT_STS_29MAY2025,
            SonicConstantsLib.TOKEN_PT_WSTKSCUSD_29MAY2025,
            SonicConstantsLib.TOKEN_PT_WSTKSCETH_29MAY2025, // 41
            SonicConstantsLib.TOKEN_PT_WOS_29MAY2025,
            SonicConstantsLib.TOKEN_PT_SILO_46_SCUSD_14AUG2025, // 43
            SonicConstantsLib.TOKEN_PT_SILO_20_USDC_17JUL2025, // 44
            SonicConstantsLib.TOKEN_GEMSX,
            SonicConstantsLib.TOKEN_BUSDCE20, // 46
            SonicConstantsLib.TOKEN_BEETSFRAGMENTSS1,
            SonicConstantsLib.TOKEN_USDT,
            SonicConstantsLib.TOKEN_SILO, // 49
            SonicConstantsLib.TOKEN_BES,
            SonicConstantsLib.SILO_VAULT_25_WS
        ];
    }

    //region --------------------------------------- Dynamic routes - metaVault

    function testSwapMetaUsdUsdc() public {
        //--------------------------------- Prepare swapper and routes
        address multisig = IPlatform(PLATFORM).multisig();

        _upgrade();
        _addAdapter();
        _addToWhitelist(address(this));

        vm.startPrank(multisig);
        swapper.addPools(_routes(), false);
        vm.stopPrank();

        IMetaVault metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);

        //--------------------------------- Set up initial balances
        uint amount = 2e6; // 1 USDC
        assertEq(metaVault.balanceOf(address(this)), 0);
        deal(SonicConstantsLib.TOKEN_USDC, address(this), amount);

        //--------------------------------- Swap USDC => metaUSD
        IERC20(SonicConstantsLib.TOKEN_USDC).approve(address(swapper), type(uint).max);
        swapper.swap(SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.METAVAULT_METAUSD, amount, 1_000);
        vm.roll(block.number + 6);

        uint balanceMetaUsd0 = metaVault.balanceOf(address(this));
        uint balanceToken0 = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this));

        assertNotEq(balanceMetaUsd0, 0, "balanceMetaUsd0 should not be 0");
        assertEq(balanceToken0, 0, "balanceToken0 should be 0");

        //--------------------------------- Swap metaUSD => USDC
        bool withdrawDirectly = metaVault.assetsForWithdraw()[0] == SonicConstantsLib.TOKEN_USDC;
        metaVault.approve(address(swapper), type(uint).max);

        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1));
        swapper.swap(SonicConstantsLib.METAVAULT_METAUSD, SonicConstantsLib.TOKEN_USDC, balanceMetaUsd0, 1_000);
        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0));

        vm.roll(block.number + 6);

        uint balanceMetaUsd1 = metaVault.balanceOf(address(this));
        uint balanceToken1 = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this));

        assertApproxEqAbs(balanceMetaUsd1, 0, 1, "balanceMetaUsd1 should be 0"); // weird we still have 1 decimal on balance
        if (withdrawDirectly) {
            assertEq(balanceToken1, amount, "balanceToken1 should be equal to initial amount");
        } else {
            assertLe(
                _getDiffPercent18(balanceToken1, amount),
                1e18 / 1000, // 0.1%
                "balanceToken1 should be equal to initial amount"
            );
        }
    }

    function testSwapMetaUsdScUsd() public {
        //--------------------------------- Prepare swapper and routes
        address multisig = IPlatform(PLATFORM).multisig();

        _upgrade();
        _addAdapter();
        _addToWhitelist(address(this));

        IMetaVault metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);

        vm.startPrank(multisig);
        swapper.addPools(_routes(), false);
        vm.stopPrank();

        //--------------------------------- Set up initial balances
        uint amount = 2e6; // 1 USDC
        assertEq(metaVault.balanceOf(address(this)), 0);
        deal(SonicConstantsLib.TOKEN_SCUSD, address(this), amount);

        //--------------------------------- Swap scUSD => metaUSD
        IERC20(SonicConstantsLib.TOKEN_SCUSD).approve(address(swapper), type(uint).max);
        swapper.swap(SonicConstantsLib.TOKEN_SCUSD, SonicConstantsLib.METAVAULT_METAUSD, amount, 1_000);
        vm.roll(block.number + 6);

        uint balanceMetaUsd0 = metaVault.balanceOf(address(this));
        uint balanceToken0 = IERC20(SonicConstantsLib.TOKEN_SCUSD).balanceOf(address(this));

        assertNotEq(balanceMetaUsd0, 0, "balanceMetaUsd0 should not be 0");
        assertEq(balanceToken0, 0, "balanceToken0 should be 0");

        //--------------------------------- Swap metaUSD => scUSD
        bool withdrawDirectly = metaVault.assetsForWithdraw()[0] == SonicConstantsLib.TOKEN_SCUSD;
        metaVault.approve(address(swapper), type(uint).max);

        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1));
        swapper.swap(SonicConstantsLib.METAVAULT_METAUSD, SonicConstantsLib.TOKEN_SCUSD, balanceMetaUsd0, 1_000);
        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0));

        vm.roll(block.number + 6);

        uint balanceMetaUsd1 = metaVault.balanceOf(address(this));
        uint balanceToken1 = IERC20(SonicConstantsLib.TOKEN_SCUSD).balanceOf(address(this));

        assertApproxEqAbs(balanceMetaUsd1, 0, 1, "balanceMetaUsd1 should be 0"); // weird we still have 1 decimal on balance
        if (withdrawDirectly) {
            assertEq(balanceToken1, amount, "balanceToken1 should be equal to initial amount");
        } else {
            assertLe(
                _getDiffPercent18(balanceToken1, amount),
                1e18 / 1000, // 0.1%
                "balanceToken1 should be equal to initial amount"
            );
        }
    }

    function testSwapMetaSToWS() public {
        //--------------------------------- Prepare swapper and routes
        address multisig = IPlatform(PLATFORM).multisig();

        _upgrade();
        _addAdapter();
        _addToWhitelist(address(this));

        vm.startPrank(multisig);
        swapper.addPools(_routes(), false);
        vm.stopPrank();

        IMetaVault metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAS);

        //--------------------------------- Set up initial balances
        uint amount = 2e18; // 2 ws
        assertEq(metaVault.balanceOf(address(this)), 0);
        deal(SonicConstantsLib.TOKEN_WS, address(this), amount);

        //--------------------------------- Swap USDC => metaUSD
        IERC20(SonicConstantsLib.TOKEN_WS).approve(address(swapper), type(uint).max);
        swapper.swap(SonicConstantsLib.TOKEN_WS, SonicConstantsLib.METAVAULT_METAS, amount, 1_000);
        vm.roll(block.number + 6);

        uint balanceMetaS0 = metaVault.balanceOf(address(this));
        uint balanceToken0 = IERC20(SonicConstantsLib.TOKEN_WS).balanceOf(address(this));

        assertNotEq(balanceMetaS0, 0, "balanceMetaS0 should not be 0");
        assertEq(balanceToken0, 0, "balanceToken0 should be 0");

        //--------------------------------- Swap metaUSD => USDC
        metaVault.approve(address(swapper), type(uint).max);

        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1));
        swapper.swap(SonicConstantsLib.METAVAULT_METAS, SonicConstantsLib.TOKEN_WS, balanceMetaS0, 1_000);
        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0));

        vm.roll(block.number + 6);

        uint balanceMetaS1 = metaVault.balanceOf(address(this));
        uint balanceToken1 = IERC20(SonicConstantsLib.TOKEN_WS).balanceOf(address(this));

        assertApproxEqAbs(balanceMetaS1, 0, 1, "balanceMetaS1 should be 0");
        assertApproxEqAbs(balanceToken1, amount, 10, "balanceToken1 should be equal to initial amount");
    }

    //endregion --------------------------------------- Dynamic routes  - metaVault

    //region --------------------------------------- Dynamic routes  - wrapped

    function testSwapWrappedMetaUsdUsdc() public {
        //--------------------------------- Prepare swapper and routes
        address multisig = IPlatform(PLATFORM).multisig();

        _upgrade();
        _addAdapter();
        _addToWhitelist(address(this));

        IMetaVault metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);

        vm.startPrank(multisig);
        swapper.addPools(_routes(), false);
        vm.stopPrank();

        //--------------------------------- Set up initial balances
        uint amount = 2e6; // 1 USDC
        assertEq(metaVault.balanceOf(address(this)), 0);
        deal(SonicConstantsLib.TOKEN_USDC, address(this), amount);

        //--------------------------------- Swap USDC => metaUSD
        IERC20(SonicConstantsLib.TOKEN_USDC).approve(address(swapper), type(uint).max);

        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1));
        swapper.swap(SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, amount, 1_000);
        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0));

        vm.roll(block.number + 6);

        uint balanceMetaUsd0 = IERC20(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).balanceOf(address(this));
        uint balanceToken0 = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this));

        assertNotEq(balanceMetaUsd0, 0, "balanceMetaUsd0 should not be 0");
        assertEq(balanceToken0, 0, "balanceToken0 should be 0");

        //--------------------------------- Swap metaUSD => USDC
        bool withdrawDirectly =
            IMetaVault(IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).metaVault())
                    .assetsForWithdraw()[0] == SonicConstantsLib.TOKEN_USDC;

        IERC20(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).approve(address(swapper), type(uint).max);

        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1));
        swapper.swap(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, SonicConstantsLib.TOKEN_USDC, balanceMetaUsd0, 1_000);
        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0));

        vm.roll(block.number + 6);

        uint balanceMetaUsd1 = IERC20(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).balanceOf(address(this));
        uint balanceToken1 = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this));

        assertApproxEqAbs(balanceMetaUsd1, 0, 1, "balanceMetaUsd1 should be 0"); // weird we still have 1 decimal on balance
        if (withdrawDirectly) {
            assertEq(balanceToken1, amount, "balanceToken1 should be equal to initial amount");
        } else {
            assertLe(
                _getDiffPercent18(balanceToken1, amount),
                1e18 / 1000, // 0.1%
                "balanceToken1 should be equal to initial amount"
            );
        }
    }

    function testSwapWrappedMetaUsdScUsd() public {
        //--------------------------------- Prepare swapper and routes
        address multisig = IPlatform(PLATFORM).multisig();

        _upgrade();
        _addAdapter();
        _addToWhitelist(address(this));

        IMetaVault metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);

        vm.startPrank(multisig);
        swapper.addPools(_routes(), false);
        vm.stopPrank();

        //--------------------------------- Set up initial balances
        uint amount = 2e6; // 1 USDC
        assertEq(IERC20(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).balanceOf(address(this)), 0);
        deal(SonicConstantsLib.TOKEN_SCUSD, address(this), amount);

        //--------------------------------- Swap scUSD => metaUSD
        IERC20(SonicConstantsLib.TOKEN_SCUSD).approve(address(swapper), type(uint).max);

        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1));
        swapper.swap(SonicConstantsLib.TOKEN_SCUSD, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, amount, 1_000);
        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0));

        vm.roll(block.number + 6);

        uint balanceMetaUsd0 = IERC20(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).balanceOf(address(this));
        uint balanceToken0 = IERC20(SonicConstantsLib.TOKEN_SCUSD).balanceOf(address(this));

        assertNotEq(balanceMetaUsd0, 0, "balanceMetaUsd0 should not be 0");
        assertEq(balanceToken0, 0, "balanceToken0 should be 0");

        //--------------------------------- Swap metaUSD => scUSD
        bool withdrawDirectly =
            IMetaVault(IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).metaVault())
                    .assetsForWithdraw()[0] == SonicConstantsLib.TOKEN_SCUSD;

        IERC20(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).approve(address(swapper), type(uint).max);

        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1));
        swapper.swap(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, SonicConstantsLib.TOKEN_SCUSD, balanceMetaUsd0, 1_000);
        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0));

        vm.roll(block.number + 6);

        uint balanceMetaUsd1 = IERC20(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).balanceOf(address(this));
        uint balanceToken1 = IERC20(SonicConstantsLib.TOKEN_SCUSD).balanceOf(address(this));

        assertApproxEqAbs(balanceMetaUsd1, 0, 1, "balanceMetaUsd1 should be 0"); // weird we still have 1 decimal on balance
        if (withdrawDirectly) {
            assertEq(balanceToken1, amount, "balanceToken1 should be equal to initial amount");
        } else {
            assertLe(
                _getDiffPercent18(balanceToken1, amount),
                1e18 / 1000, // 0.1%
                "balanceToken1 should be equal to initial amount"
            );
        }
    }

    function testSwapWrappedMetaBadPaths() public {
        //--------------------------------- Prepare swapper and routes
        address multisig = IPlatform(PLATFORM).multisig();
        address whitelisted = makeAddr("whitelisted");

        _upgrade();
        _addAdapter();
        _addToWhitelist(whitelisted);

        IMetaVault metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);

        vm.startPrank(multisig);
        swapper.addPools(_routes(), false);
        vm.stopPrank();

        //--------------------------------- Ensure that swap is not possible without setLastBlockDefenseDisabledTx
        deal(SonicConstantsLib.TOKEN_SCUSD, address(this), 1e6);
        IERC20(SonicConstantsLib.TOKEN_SCUSD).approve(address(swapper), type(uint).max);

        vm.expectRevert(IStabilityVault.WaitAFewBlocks.selector);
        swapper.swap(SonicConstantsLib.TOKEN_SCUSD, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, 1e6, 1_000);

        //--------------------------------- Disable protection => swap works fine
        vm.prank(whitelisted);
        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1));

        swapper.swap(SonicConstantsLib.TOKEN_SCUSD, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, 1e6, 1_000);
        // suppose, we forget to enable protection back
        // metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0));

        vm.roll(block.number + 6); // protection is automatically enabled after changing block

        //----------------------- Ensure that swap is not possible without setLastBlockDefenseDisabledTx
        deal(SonicConstantsLib.TOKEN_SCUSD, address(this), 1e6);
        IERC20(SonicConstantsLib.TOKEN_SCUSD).approve(address(swapper), type(uint).max);

        vm.expectRevert(IStabilityVault.WaitAFewBlocks.selector);
        swapper.swap(SonicConstantsLib.TOKEN_SCUSD, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, 1e6, 1_000);

        //----------------------- Disable protection => swap works fine
        vm.prank(whitelisted);
        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1));

        swapper.swap(SonicConstantsLib.TOKEN_SCUSD, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, 1e6, 1_000);

        vm.prank(whitelisted);
        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0));

        // --------------------- block is NOT changed, protection is enabled back - now it's not possible to swap again
        deal(SonicConstantsLib.TOKEN_SCUSD, address(this), 1e6);
        IERC20(SonicConstantsLib.TOKEN_SCUSD).approve(address(swapper), type(uint).max);

        vm.expectRevert(IStabilityVault.WaitAFewBlocks.selector);
        swapper.swap(SonicConstantsLib.TOKEN_SCUSD, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, 1e6, 1_000);
    }

    //endregion --------------------------------------- Dynamic routes  - wrapped

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

    //region --------------------------------------- Tests to find cycling routes #261 (change internal to public to enable)

    function testSearchProblemRoutes__Fuzzy(uint from, uint to) internal view {
        from = bound(from, 0, tokens.length - 1);
        to = bound(to, 0, tokens.length - 1);
        if (from == to) {
            return; // no route
        }

        (ISwapper.PoolData[] memory route,) = swapper.buildRoute(tokens[from], tokens[to]);
        if (route.length != 0) {
            if (_isCycling(route) && !_isKnownCyclingPair(tokens[from], tokens[to])) {
                _displayRoute(route, from, to, tokens[from], tokens[to]);
                assertEq(false, true);
            }
        }
    }

    function testSearchProblemRoutesCycle(uint from, uint to) internal view {
        from = bound(from, 0, tokens.length - 1);
        to = bound(to, 0, tokens.length - 1);
        if (from == to) {
            return; // no route
        }

        for (uint i = 0; i < tokens.length; ++i) {
            for (uint j = i; j < tokens.length; ++j) {
                (ISwapper.PoolData[] memory route,) = swapper.buildRoute(tokens[from], tokens[to]);
                if (route.length != 0) {
                    if (_isCycling(route) && !_isKnownCyclingPair(tokens[from], tokens[to])) {
                        console.log("!!!!!!!!!!!Cycling route found for:", tokens[from], tokens[to]);
                        _displayRoute(route, from, to, tokens[from], tokens[to]);
                    }
                }
            }
        }
    }

    //endregion --------------------------------------- Tests to find cycling routes #261 (change internal to public to enable)

    //region --------------------------------------- Internal logic
    function _displayRoute(
        ISwapper.PoolData[] memory route,
        uint from,
        uint to,
        address tokenIn,
        address tokenOut
    ) internal view {
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

    function _isKnownCyclingPair(address tokenIn, address tokenOut) internal view returns (bool) {
        for (uint i = 0; i < KNOWN_CYCLING_PAIRS.length; i++) {
            if (
                (KNOWN_CYCLING_PAIRS[i][0] == tokenIn && KNOWN_CYCLING_PAIRS[i][1] == tokenOut)
                    || (KNOWN_CYCLING_PAIRS[i][0] == tokenOut && KNOWN_CYCLING_PAIRS[i][1] == tokenIn)
            ) {
                return true;
            }
        }
        return false;
    }

    //endregion --------------------------------------- Internal logic

    //region --------------------------------------- Helper functions
    function _addToWhitelist(address whitelistedUser) internal {
        address multisig = IPlatform(PLATFORM).multisig();

        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAS);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSD).changeWhitelist(whitelistedUser, true);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAS).changeWhitelist(whitelistedUser, true);
    }

    function _addAdapter() internal returns (address adapter) {
        address multisig = IPlatform(PLATFORM).multisig();
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new MetaVaultAdapter()));
        MetaVaultAdapter(address(proxy)).init(PLATFORM);

        vm.prank(multisig);
        IPlatform(PLATFORM).addAmmAdapter(AmmAdapterIdLib.META_VAULT, address(proxy));

        return address(proxy);
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
        pools = new ISwapper.AddPoolData[](4);
        uint i;
        pools[i++] = _makePoolData(
            SonicConstantsLib.METAVAULT_METAUSD,
            AmmAdapterIdLib.META_VAULT,
            SonicConstantsLib.METAVAULT_METAUSD,
            SonicConstantsLib.METAVAULT_METAUSD
        );
        pools[i++] = _makePoolData(
            SonicConstantsLib.WRAPPED_METAVAULT_METAUSD,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.WRAPPED_METAVAULT_METAUSD,
            SonicConstantsLib.METAVAULT_METAUSD
        );
        pools[i++] = _makePoolData(
            SonicConstantsLib.METAVAULT_METAS,
            AmmAdapterIdLib.META_VAULT,
            SonicConstantsLib.METAVAULT_METAS,
            SonicConstantsLib.METAVAULT_METAS
        );
        pools[i++] = _makePoolData(
            SonicConstantsLib.WRAPPED_METAVAULT_METAS,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.WRAPPED_METAVAULT_METAS,
            SonicConstantsLib.METAVAULT_METAS
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

    function _upgradeMetaVault(address metaVault_) internal {
        IMetaVaultFactory metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());
        address multisig = IPlatform(PLATFORM).multisig();

        // Upgrade MetaVault to the new implementation
        address vaultImplementation = address(new MetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);
        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault_);
        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);
    }

    function _getDiffPercent18(uint x, uint y) internal pure returns (uint) {
        return x > y ? (x - y) * 1e18 / x : (y - x) * 1e18 / x;
    }
    //endregion --------------------------------------- Helper functions
}
