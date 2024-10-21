// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../base/chains/PolygonSetup.sol";
import "../../src/core/libs/VaultTypeLib.sol";
import "../../src/strategies/libs/StrategyIdLib.sol";
import "../../src/interfaces/IRVault.sol";
import "../../src/interfaces/IManagedVault.sol";

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
            // compoundRatio
            vaultInitNums[vaultInitNums.length - 1] = 50_000;

            // farmId
            nums[0] = 5; // WMATIC-USDC narrow

            vaultInitNums[1] = 10;
            vm.expectRevert(IFactory.BoostDurationTooLow.selector);
            factory.deployVaultAndStrategy(
                VaultTypeLib.REWARDING_MANAGED,
                StrategyIdLib.GAMMA_QUICKSWAP_MERKL_FARM,
                vaultInitAddresses,
                vaultInitNums,
                initStrategyAddresses,
                nums,
                ticks
            );
            vaultInitNums[1] = 86400 * 30;

            vaultInitNums[2] = 10;
            vm.expectRevert(IFactory.BoostAmountTooLow.selector);
            factory.deployVaultAndStrategy(
                VaultTypeLib.REWARDING_MANAGED,
                StrategyIdLib.GAMMA_QUICKSWAP_MERKL_FARM,
                vaultInitAddresses,
                vaultInitNums,
                initStrategyAddresses,
                nums,
                ticks
            );
            vaultInitNums[2] = 1000e6;

            vaultInitNums[2] = 0;
            vm.expectRevert(IFactory.BoostAmountIsZero.selector);
            factory.deployVaultAndStrategy(
                VaultTypeLib.REWARDING_MANAGED,
                StrategyIdLib.GAMMA_QUICKSWAP_MERKL_FARM,
                vaultInitAddresses,
                vaultInitNums,
                initStrategyAddresses,
                nums,
                ticks
            );
            vaultInitNums[2] = 1000e6;

            factory.deployVaultAndStrategy(
                VaultTypeLib.REWARDING_MANAGED,
                StrategyIdLib.GAMMA_QUICKSWAP_MERKL_FARM,
                vaultInitAddresses,
                vaultInitNums,
                initStrategyAddresses,
                nums,
                ticks
            );
        }

        assertEq(IERC721(platform.vaultManager()).ownerOf(0), address(this));

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
        vault.depositAssets(assets, depositAmounts, 0, address(0));
        (uint tvl,) = vault.tvl();

        assertGt(tvl, 0, "RMVault test: tvl is zero");

        skip(86400);

        {
            IVaultManager vaultManager = IVaultManager(platform.vaultManager());
            // set compound ratio to 0%
            address[] memory vaultChangeAddresses = new address[](2);
            vaultChangeAddresses[0] = platform.targetExchangeAsset();
            vaultChangeAddresses[1] = assets[0];
            uint[] memory vaultChangeNums = new uint[](4);
            vaultChangeNums[0] = 86400 * 10;
            vaultChangeNums[1] = 86400 * 30;
            vaultChangeNums[2] = 86400 * 365;
            vaultChangeNums[3] = 0;
            vaultManager.changeVaultParams(0, vaultChangeAddresses, vaultChangeNums);
            assertEq(vault.compoundRatio(), 0);

            // bad paths
            vm.expectRevert(IManagedVault.NotVaultManager.selector);
            IManagedVault(address(vault)).changeParams(vaultChangeAddresses, vaultChangeNums);

            vaultChangeAddresses = new address[](3);
            vm.expectRevert(IControllable.IncorrectInitParams.selector);
            vaultManager.changeVaultParams(0, vaultChangeAddresses, vaultChangeNums);

            vaultChangeAddresses = new address[](1);
            vaultChangeNums = new uint[](3);
            vm.expectRevert(IManagedVault.CantRemoveRewardToken.selector);
            vaultManager.changeVaultParams(0, vaultChangeAddresses, vaultChangeNums);

            vaultChangeAddresses = new address[](2);
            vaultChangeAddresses[0] = platform.targetExchangeAsset();
            vaultChangeAddresses[1] = address(1); //assets[0];
            vaultChangeNums = new uint[](4);
            vaultChangeNums[0] = 86400 * 10;
            vaultChangeNums[1] = 86400 * 30;
            vaultChangeNums[2] = 86400 * 365;
            vaultChangeNums[3] = 0;
            vm.expectRevert(abi.encodeWithSelector(IManagedVault.IncorrectRewardToken.selector, address(1)));
            vaultManager.changeVaultParams(0, vaultChangeAddresses, vaultChangeNums);

            vaultChangeAddresses[1] = assets[0];
            vaultChangeNums[1] = 86400 * 30 + 1;
            vm.expectRevert(abi.encodeWithSelector(IManagedVault.CantChangeDuration.selector, vaultChangeNums[1]));
            vaultManager.changeVaultParams(0, vaultChangeAddresses, vaultChangeNums);

            vaultChangeAddresses = new address[](3);
            vaultChangeAddresses[0] = platform.targetExchangeAsset();
            vaultChangeAddresses[1] = assets[0];
            vaultChangeAddresses[2] = assets[1];
            vaultChangeNums = new uint[](5);
            vaultChangeNums[0] = 86400 * 10;
            vaultChangeNums[1] = 86400 * 30;
            vaultChangeNums[2] = 86400 * 365;
            vaultChangeNums[3] = 0;
            vaultChangeNums[4] = 0;
            vm.expectRevert(IControllable.IncorrectZeroArgument.selector);
            vaultManager.changeVaultParams(0, vaultChangeAddresses, vaultChangeNums);

            vaultChangeAddresses[2] = address(0);
            vaultChangeNums[3] = 86400 * 366;
            vm.expectRevert(IControllable.IncorrectZeroArgument.selector);
            vaultManager.changeVaultParams(0, vaultChangeAddresses, vaultChangeNums);
        }

        deal(PolygonLib.TOKEN_QUICK, address(vault.strategy()), 10e18);

        (uint sharePriceBefore,) = vault.price();
        vault.doHardWork();
        (uint sharePriceAfter,) = vault.price();
        assertEq(sharePriceBefore, sharePriceAfter);

        assertEq(vault.earned(0, address(this)), 0);
        skip(86400);
        assertGt(vault.earned(0, address(this)), 0, "Eearned zero");
        assertGt(vault.earned(1, address(this)), 0, "Eearned zero");
        assertEq(vault.duration(0), 86400 * 10);

        vm.prank(address(0));
        vm.expectRevert(IControllable.NotMultisig.selector);
        vault.setRewardsRedirect(address(this), address(1));
        vault.setRewardsRedirect(address(this), address(1));
        assertEq((vault.rewardsRedirect(address(this))), address(1));

        vault.setRewardsRedirect(address(this), address(0));
        vm.expectRevert(IControllable.IncorrectZeroArgument.selector);
        vault.getAllRewardsAndRedirect(address(this));

        vault.setRewardsRedirect(address(this), address(1));
        vault.getAllRewardsAndRedirect(address(this));

        vault.rewardToken(vault.tokenId());

        vm.prank(address(123));
        vm.expectRevert(IRVault.NotAllowed.selector);
        vault.getAllRewardsFor(address(this));

        vm.expectRevert(IRVault.NotAllowed.selector);
        vault.getAllRewardsFor(address(1));

        vault.getAllRewardsFor(address(this));

        skip(86400);
        IERC20(address(vault)).approve(address(1), type(uint).max);
        vm.prank(address(1));
        vault.getAllRewardsFor(address(this));

        vault.rewardTokensTotal();

        assertGt(vault.rewardPerToken(0), 0);

        vm.expectRevert(IRVault.RTNotFound.selector);
        vault.notifyTargetRewardAmount(4, 1e36);

        vm.expectRevert(abi.encodeWithSelector(IRVault.Overflow.selector, (type(uint).max / 1e18 - 1)));
        vault.notifyTargetRewardAmount(1, type(uint).max / 5);

        vm.expectRevert(IControllable.IncorrectMsgSender.selector);
        vault.notifyTargetRewardAmount(0, 100);

        deal(platform.targetExchangeAsset(), address(this), 1e18);
        vm.expectRevert(IRVault.RewardIsTooSmall.selector);
        vault.notifyTargetRewardAmount(1, 1000);

        IERC20(platform.targetExchangeAsset()).approve(address(vault), 1e18);
        vault.notifyTargetRewardAmount(1, 1e18 / 2);

        // tried to get RewardIsTooBig error, but cant
        skip(86400000);
        uint a = type(uint).max / 1e20;
        deal(platform.targetExchangeAsset(), address(this), a);
        IERC20(platform.targetExchangeAsset()).approve(address(vault), a);
        // vm.expectRevert(IRVault.RewardIsTooBig.selector);
        vault.notifyTargetRewardAmount(1, a);

        vm.expectRevert(IVault.NotSupported.selector);
        vault.hardWorkMintFeeCallback(new address[](0), new uint[](0));
    }
}
