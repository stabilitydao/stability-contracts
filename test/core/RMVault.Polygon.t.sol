// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../base/chains/PolygonSetup.sol";
import "../../src/core/libs/VaultTypeLib.sol";
import "../../src/strategies/libs/StrategyIdLib.sol";
import "../../src/interfaces/IRVault.sol";

contract RMVaultTest is PolygonSetup {
    constructor() {
        _init();

        deal(platform.buildingPayPerVaultToken(), address(this), 5e24);
        IERC20(platform.buildingPayPerVaultToken()).approve(address(factory), 5e24);

        deal(platform.targetExchangeAsset(), address(this), 1e9);
        IERC20(platform.targetExchangeAsset()).approve(address(factory), 1e9);
    }

    function testRewards() public {
        {
            address[] memory vaultInitAddresses = new address[](2);
            uint vaultInitAddressesLength = vaultInitAddresses.length;
            uint[] memory vaultInitNums = new uint[](vaultInitAddressesLength * 2);
            address[] memory initStrategyAddresses = new address[](0);
            uint[] memory nums = new uint[](1);
            int24[] memory ticks = new int24[](0);

            // bbToken
            vaultInitAddresses[0] = platform.allowedBBTokens()[0];
            // boost reward tokens
            vaultInitAddresses[1] = platform.targetExchangeAsset();
            // bbToken vesting duration
            vaultInitNums[0] = 86400 * 10;
            for (uint e = 1; e < vaultInitAddressesLength; ++e) {
                vaultInitNums[e] = 86400 * 30;
                vaultInitNums[e + vaultInitAddressesLength - 1] = 1000e6; // 1000 usdc
            }
            // compoundRatuo
            vaultInitNums[vaultInitNums.length - 1] = 50_000;

            // farmId
            nums[0] = 6; // WMATIC-USDC narrow

            factory.deployVaultAndStrategy(VaultTypeLib.REWARDING_MANAGED, StrategyIdLib.GAMMA_QUICKSWAP_FARM, vaultInitAddresses, vaultInitNums, initStrategyAddresses, nums, ticks);
        }

        assertEq(IERC721(platform.vaultManager()).ownerOf(0), address (this));

        IRVault vault = IRVault(factory.deployedVault(0));
        IStrategy strategy = vault.strategy();
        address[] memory assets = strategy.assets();
        uint[] memory depositAmounts = new uint[](2);
        depositAmounts[0] = 1000e18;
        depositAmounts[1] = 1000e6;
        deal(assets[0], address(this), depositAmounts[0]);
        deal(assets[1], address(this), depositAmounts[1]);
        IERC20(assets[0]).approve(address(vault), depositAmounts[0]);
        IERC20(assets[1]).approve(address(vault), depositAmounts[1]);

        // deposit
        vault.depositAssets(assets, depositAmounts, 0);
        (uint tvl, ) = vault.tvl();
        assertGt(tvl, 0, "RMVault test: tvl is zero");

        skip(86400);

        {
            // set compound ratiio to 0%
            address[] memory vaultChangeAddresses = new address[](2);
            vaultChangeAddresses[0] = platform.targetExchangeAsset();
            vaultChangeAddresses[1] = assets[0];
            uint[] memory vaultChangeNums = new uint[](4);
            vaultChangeNums[0] = 86400 * 10;
            vaultChangeNums[1] = 86400 * 30;
            vaultChangeNums[2] = 86400 * 365;
            vaultChangeNums[3] = 0;

            IVaultManager(platform.vaultManager()).changeVaultParams(0, vaultChangeAddresses, vaultChangeNums);
            assertEq(vault.compoundRatio(), 0);

        }
        
        (uint sharePriceBefore,) = vault.price();
        vault.doHardWork();
        (uint sharePricieAfter,) = vault.price();
        assertEq(sharePriceBefore, sharePricieAfter);

        assertEq(vault.earned(0, address(this)), 0);
        skip(86400);
        assertGt(vault.earned(0, address(this)), 0);
        assertGt(vault.earned(1, address(this)), 0);
        assertEq(vault.duration(0), 86400 * 10);

        // todo test setRewardsRedirect, getAllRewardsFor
    }
}
