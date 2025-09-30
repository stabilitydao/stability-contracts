// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {Platform} from "../../src/core/Platform.sol";
import {Recovery} from "../../src/tokenomics/Recovery.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {console, Test} from "forge-std/Test.sol";
import {Swapper} from "../../src/core/Swapper.sol";
import {MetaVaultAdapter} from "../../src/adapters/MetaVaultAdapter.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";

contract RecoveryUpgradeTestSonic is Test {
    uint public constant FORK_BLOCK = 48796315; // Sep-30-2025 02:52:14 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(PLATFORM).multisig();

        _upgradePlatform();
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAS);
        //        _upgradeCVault(0x38274302e0Dd5779b4E0A3E401023cFB48fF5c23);
        //        _upgradeSiloStrategy(0xaB7F5bA1Ea7434730a3976a45662833E6a6D0bC0);
    }

    function testSwapAssetsToRecoveryTokens() public {
        IRecovery recovery = IRecovery(IPlatform(PLATFORM).recovery());
        //        IPriceReader priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());

        // ------------------------------ Get list of available tokes and their prices
        {
            address[] memory tokens = recovery.getListTokensToSwap();
            //            for (uint i = 0; i < tokens.length; i++) {
            //                address token = tokens[i];
            //                uint balance = IERC20(token).balanceOf(address(recovery));
            //                (uint price, ) = priceReader.getPrice(token);
            //                console.log(token, balance, price, IERC20Metadata(token).decimals());
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
        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).removeVault(0x8913582701B7c80E883F9E352c1653a16769B173);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).removeVault(0x0c8cE5afC38C94e163F0dDEB2Da65DF4904734f3);

        console.log("vault for deposit", IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).vaultForDeposit());

        // ------------------------------ Swap all assets by portions
        address[] memory tokensToSwap = recovery.getListTokensToSwap();
        uint tokensPerStep = 1;
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
            console.log("swap", gasBefore - gasAfter);

            // todo assertLt(gasBefore - gasAfter, 5_000_000, "gas limit exceeded");
        }

        // ------------------------------ Fill up recovery pools
        {
            uint gasBefore = gasleft();
            vm.prank(multisig);
            recovery.fillRecoveryPools(SonicConstantsLib.METAVAULT_METAUSD, 0, 0);
            uint gasAfter = gasleft();
            console.log("fill meta USD", gasBefore - gasAfter);

            // todo assertLt(gasBefore - gasAfter, 5_000_000, "gas limit exceeded");
        }
        {
            uint gasBefore = gasleft();
            vm.prank(multisig);
            recovery.fillRecoveryPools(SonicConstantsLib.METAVAULT_METAS, 0, 0);
            uint gasAfter = gasleft();
            console.log("fill metaS", gasBefore - gasAfter);

            // todo assertLt(gasBefore - gasAfter, 5_000_000, "gas limit exceeded");
        }
    }

    function _upgradePlatform() internal {
        rewind(1 days);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = platform.recovery();
        //        proxies[1] = platform.swapper();
        //        proxies[2] = platform.ammAdapter(keccak256(bytes(AmmAdapterIdLib.META_VAULT))).proxy;
        implementations[0] = address(new Recovery());
        //        implementations[1] = address(new Swapper());
        //        implementations[2] = address(new MetaVaultAdapter());

        vm.startPrank(platform.multisig());
        platform.announcePlatformUpgrade("2025.10.01-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }

    function _upgradeMetaVault(address metaVault_) internal {
        IMetaVaultFactory metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);

        // Upgrade MetaVault to the new implementation
        address vaultImplementation = address(new MetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);
        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault_);
        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);
    }

    //    function _upgradeSiloStrategy(address strategyAddress) internal {
    //        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
    //
    //        address strategyImplementation = address(new SiloStrategy());
    //        vm.prank(multisig);
    //        factory.setStrategyLogicConfig(
    //            IFactory.StrategyLogicConfig({
    //                id: StrategyIdLib.SILO,
    //                implementation: strategyImplementation,
    //                deployAllowed: true,
    //                upgradeAllowed: true,
    //                farming: true,
    //                tokenId: 0
    //            }),
    //            address(this)
    //        );
    //
    //        factory.upgradeStrategyProxy(strategyAddress);
    //    }
    //
    //    function _upgradeCVault(address vault) internal {
    //        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
    //
    //        // deploy new impl and upgrade
    //        address vaultImplementation = address(new CVault());
    //        vm.prank(multisig);
    //        factory.setVaultConfig(
    //            IFactory.VaultConfig({
    //                vaultType: VaultTypeLib.COMPOUNDING,
    //                implementation: vaultImplementation,
    //                deployAllowed: true,
    //                upgradeAllowed: true,
    //                buildingPrice: 1e10
    //            })
    //        );
    //        factory.upgradeVaultProxy(address(vault));
    //    }
}
