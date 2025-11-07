// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import {console} from "forge-std/console.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {Recovery} from "../../src/tokenomics/Recovery.sol";
import {RecoveryLib} from "../../src/tokenomics/libs/RecoveryLib.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Test} from "forge-std/Test.sol";

contract RecoveryUpgradeTestSonic is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;

    constructor() {}

    function testGetPoolWithNonUnitPrice() public {
        _setUpTest(53711121); // Nov-05-2025 05:07:58 AM +UTC

        IRecovery recovery = IRecovery(IPlatform(PLATFORM).recovery());
        address[] memory pools = recovery.recoveryPools();

        for (uint i; i < 5; ++i) {
            assertEq(RecoveryLib.selectPool(i, pools), 2, "pool 2 has min price");
        }

        // --------------- Make swap in Recovery-metaS-related pool
        {
            ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());
            deal(SonicConstantsLib.RECOVERY_TOKEN_CREDIX_WMETAS, address(this), 100e18);
            IERC20(SonicConstantsLib.RECOVERY_TOKEN_CREDIX_WMETAS).approve(address(swapper), type(uint).max);
            swapper.swap(
                SonicConstantsLib.RECOVERY_TOKEN_CREDIX_WMETAS,
                SonicConstantsLib.WRAPPED_METAVAULT_METAS,
                100e18,
                90_000
            );
            assertEq(RecoveryLib.selectPool(0, pools), 5, "now pool 5 has min price");
        }
    }

    function testSwapExplicitly() public {
        // _setUpTest(53711121); // Nov-05-2025 05:07:58 AM +UTC
        _setUpTest(52711121);
        // _setUpTest(53711121); // Nov-05-2025 05:07:58 AM +UTC
        address multisig = IPlatform(PLATFORM).multisig();

        IRecovery recovery = IRecovery(IPlatform(PLATFORM).recovery());
        uint[2] memory balanceBefore = [
            IERC20(SonicConstantsLib.WRAPPED_METAVAULT_METAS).balanceOf(address(recovery)),
            IERC20(SonicConstantsLib.TOKEN_WS).balanceOf(address(recovery))
        ];
        assertNotEq(balanceBefore[0], 0, "there is wmetaS on balance");

        // --------------------------------- not operator
        vm.prank(address(this));
        vm.expectRevert(IControllable.NotOperator.selector);
        recovery.swapExplicitly(
            SonicConstantsLib.WRAPPED_METAVAULT_METAS, SonicConstantsLib.TOKEN_WS, balanceBefore[0], 10_000
        );

        // --------------------------------- not sufficient balance
        vm.prank(multisig);
        vm.expectRevert(IControllable.InsufficientBalance.selector);
        recovery.swapExplicitly(
            SonicConstantsLib.WRAPPED_METAVAULT_METAS, SonicConstantsLib.TOKEN_WS, balanceBefore[0] + 1, 10_000
        );

        // --------------------------------- successful swap
        vm.prank(multisig);
        IPlatform(PLATFORM).addOperator(address(this));

        uint gas = gasleft();
        vm.prank(address(this));
        recovery.swapExplicitly(
            SonicConstantsLib.WRAPPED_METAVAULT_METAS, SonicConstantsLib.TOKEN_WS, balanceBefore[0], 10_000
        );
        assertLt(gas - gasleft(), 6e6, "gas limit exceeded");

        uint[2] memory balanceAfter = [
            IERC20(SonicConstantsLib.WRAPPED_METAVAULT_METAS).balanceOf(address(recovery)),
            IERC20(SonicConstantsLib.TOKEN_WS).balanceOf(address(recovery))
        ];

        assertEq(balanceAfter[0], 0, "all wmetaS swapped");
        assertGt(balanceAfter[1], balanceAfter[0], "wS received");
    }

    function testSwapExplicitlyStsToWMetaUsd() public {
        _setUpTest(52711121);
        // _setUpTest(53711121); // Nov-05-2025 05:07:58 AM +UTC

        IRecovery recovery = IRecovery(IPlatform(PLATFORM).recovery());
        uint[2] memory balanceBefore = [
            IERC20(SonicConstantsLib.TOKEN_STS).balanceOf(address(recovery)),
            IERC20(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).balanceOf(address(recovery))
        ];
        assertNotEq(balanceBefore[0], 0, "there is stS on balance");

        // --------------------------------- not operator
        vm.prank(address(this));
        vm.expectRevert(IControllable.NotOperator.selector);
        recovery.swapExplicitly(
            SonicConstantsLib.TOKEN_STS, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, balanceBefore[0], 10_000
        );

        // --------------------------------- successful swap
        address multisig = IPlatform(PLATFORM).multisig();
        vm.prank(multisig);
        IPlatform(PLATFORM).addOperator(address(this));

        vm.prank(address(this));
        recovery.swapExplicitly(
            SonicConstantsLib.TOKEN_STS, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, balanceBefore[0], 10_000
        );

        uint[2] memory balanceAfter = [
            IERC20(SonicConstantsLib.TOKEN_STS).balanceOf(address(recovery)),
            IERC20(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).balanceOf(address(recovery))
        ];

        //        console.log("before", balanceBefore[0], balanceBefore[1]);
        //        console.log("after", balanceAfter[0], balanceAfter[1]);

        assertEq(balanceAfter[0], 0, "all stS swapped");
        assertGt(balanceAfter[1], balanceAfter[0], "wmetaUSD received");
    }

    function testSwapAssetsToRecoveryTokens() public {
        _setUpTest(48796315); // Sep-30-2025 02:52:14 AM +UTC
        address multisig = IPlatform(PLATFORM).multisig();

        IRecovery recovery = IRecovery(IPlatform(PLATFORM).recovery());

        IPriceReader priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());

        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(address(recovery), true);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSD).changeWhitelist(address(recovery), true);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAS).changeWhitelist(address(recovery), true);

        // ------------------------------ Get list of available tokes and their prices
        {
            address[] memory tokens = recovery.getListTokensToSwap();
            //            for (uint i = 0; i < tokens.length; i++) {
            //                address token = tokens[i];
            //                uint balance = IERC20(token).balanceOf(address(recovery));
            //                (uint price,) = priceReader.getPrice(token);
            //                 console.log(token, balance, price, IERC20Metadata(token).decimals());
            //            }
            assertEq(tokens.length, 15);
        }

        // ------------------------------ Set up thresholds
        {
            address[15] memory assets = [
                0x29219dd400f2Bf60E5a23d13Be72B486D4038894,
                0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE,
                0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38,
                0x871A101Dcf22fE4fE37be7B654098c801CBA1c88,
                0xfA85Fe5A8F5560e9039C04f2b0a90dE1415aBD70,
                0x420df605D062F8611EFb3F203BF258159b8FfFdE,
                0x930441Aa7Ab17654dF5663781CA0C02CC17e6643,
                0xE8a41c62BB4d5863C6eadC96792cFE90A1f37C47,
                0x9fb76f7ce5FCeAA2C42887ff441D46095E494206,
                0xa2161E75EDf50d70544e6588788A5732A3105c00,
                0xBe27993204Ec64238F71A527B4c4D5F4949034C3,
                0x9F0dF7799f6FDAd409300080cfF680f5A23df4b1,
                0xE5DA20F15420aD15DE0fa650600aFc998bbE3955,
                0x9731842eD581816913933c01De142C7EE412A8c8,
                0x77d8F09053c28FaF1E00Df6511b23125d438616f
            ];

            uint72[15] memory thresholds = [
                5000000,
                5000000,
                25000000000000000000,
                25000000000000000000,
                20000000000000000000,
                25000000000000000000,
                5000000,
                2000000000000000,
                5000000,
                2000000000000000,
                5000000,
                20000000000000000000,
                20000000000000000000,
                5000000,
                5000000
            ];

            uint[] memory targetThresholds = new uint[](thresholds.length);
            address[] memory targetAssets = new address[](thresholds.length);
            for (uint i = 0; i < thresholds.length; i++) {
                targetThresholds[i] = thresholds[i];
                targetAssets[i] = assets[i];
            }

            vm.prank(multisig);
            recovery.setThresholds(targetAssets, targetThresholds);
        }

        // ------------------------------ Get list of available tokes and their prices
        {
            address[] memory tokens = recovery.getListTokensToSwap();
            //            for (uint i = 0; i < tokens.length; i++) {
            //                address token = tokens[i];
            //                uint balance = IERC20(token).balanceOf(address(recovery));
            //                (uint price, ) = priceReader.getPrice(token);
            //                console.log(token, balance, price, IERC20Metadata(token).decimals());
            //            }
            assertEq(tokens.length, 4);
        }

        // ------------------------------ Remove deprecated vaults from metavaults
        //        vm.prank(multisig);
        //        IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).removeVault(0x8913582701B7c80E883F9E352c1653a16769B173);
        //
        //        vm.prank(multisig);
        //        IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).removeVault(0x0c8cE5afC38C94e163F0dDEB2Da65DF4904734f3);

        // ------------------------------ Swap all assets by portions
        address[] memory tokensToSwap = recovery.getListTokensToSwap();
        uint tokensPerStep = 2;
        for (uint i; i < tokensToSwap.length / tokensPerStep + 1; i++) {
            uint from = i * tokensPerStep;
            uint to = (i + 1) * tokensPerStep;
            if (to > tokensToSwap.length) {
                to = tokensToSwap.length;
            }
            if (from >= to) {
                break;
            }

            address[] memory portion = new address[](to - from);
            for (uint j = from; j < to; j++) {
                portion[j - from] = tokensToSwap[j];
            }

            uint gasBefore = gasleft();

            vm.prank(multisig);
            recovery.swapAssets(portion, 0);
            uint gasAfter = gasleft();
            // console.log("swap", gasBefore - gasAfter);

            assertLt(gasBefore - gasAfter, 13_000_000, "gas limit exceeded");
        }

        // ------------------------------ Ensure that all tokens below thresholds now
        {
            address[] memory tokens = recovery.getListTokensToSwap();
            //            for (uint i = 0; i < tokens.length; i++) {
            //                address token = tokens[i];
            //                uint balance = IERC20(token).balanceOf(address(recovery));
            //                (uint price, ) = priceReader.getPrice(token);
            //                console.log(token, balance, price, IERC20Metadata(token).decimals());
            //            }
            assertEq(tokens.length, 0);
        }

        // ------------------------------ Fill up recovery pools
        {
            uint gasBefore = gasleft();
            vm.prank(multisig);
            recovery.fillRecoveryPools(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, 0, 0);
            uint gasAfter = gasleft();
            // console.log("fill meta USD", gasBefore - gasAfter);

            assertLt(gasBefore - gasAfter, 2_000_000, "gas limit exceeded");
        }
        {
            uint gasBefore = gasleft();
            vm.prank(multisig);
            recovery.fillRecoveryPools(SonicConstantsLib.WRAPPED_METAVAULT_METAS, 0, 0);
            uint gasAfter = gasleft();
            // console.log("fill metaS", gasBefore - gasAfter);

            assertLt(gasBefore - gasAfter, 2_000_000, "gas limit exceeded");
        }
    }

    //region ------------------- Helpers
    function _setUpTest(uint forkBlock) internal {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), forkBlock));

        _upgradePlatform();
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAS);
        //        _upgradeCVault(0x38274302e0Dd5779b4E0A3E401023cFB48fF5c23);
        //        _upgradeSiloStrategy(0xaB7F5bA1Ea7434730a3976a45662833E6a6D0bC0);
    }

    function _upgradePlatform() internal {
        rewind(1 days);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = platform.recovery();
        // proxies[1] = platform.swapper();
        //        proxies[2] = platform.ammAdapter(keccak256(bytes(AmmAdapterIdLib.META_VAULT))).proxy;
        implementations[0] = address(new Recovery());
        // implementations[1] = address(new Swapper());
        //        implementations[2] = address(new MetaVaultAdapter());

        if (platform.pendingPlatformUpgrade().proxies.length != 0) {
            vm.startPrank(platform.multisig());
            platform.cancelUpgrade();
        }

        vm.startPrank(platform.multisig());
        platform.announcePlatformUpgrade("2025.10.01-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }

    function _upgradeMetaVault(address metaVault_) internal {
        IPlatform platform = IPlatform(PLATFORM);
        IMetaVaultFactory metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);

        // Upgrade MetaVault to the new implementation
        address vaultImplementation = address(new MetaVault());
        vm.prank(platform.multisig());
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);
        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault_);
        vm.prank(platform.multisig());
        metaVaultFactory.upgradeMetaProxies(metaProxies);
    }

    //endregion ------------------- Helpers
}
