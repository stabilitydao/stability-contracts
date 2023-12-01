// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import "../base/FullMockSetup.sol";

contract VaultSharePrice is Test, FullMockSetup {
    CVault public vault;

    function setUp() public {
        address[] memory addresses = new address[](3);
        addresses[1] = address(lp);
        addresses[2] = address(tokenA);
        uint[] memory nums = new uint[](0);
        int24[] memory ticks = new int24[](0);
        builderPermitToken.mint();
        factory.deployVaultAndStrategy(
            VaultTypeLib.COMPOUNDING, StrategyIdLib.DEV, new address[](0), new uint[](0), addresses, nums, ticks
        );
        vault = CVault(payable(factory.deployedVault(0)));
    }

    function testSharePriceAndTVL() public {
        address[] memory assets = new address[](2);
        assets[0] = address(tokenA);
        assets[1] = address(tokenB);
        uint[] memory amounts = new uint[](2);
        amounts[0] = 10e18; // $10
        amounts[1] = 10e6; // $20
        tokenA.mint(amounts[0]);
        tokenB.mint(amounts[1]);
        tokenA.approve(address(vault), amounts[0]);
        tokenB.approve(address(vault), amounts[1]);

        vault.depositAssets(assets, amounts, 0, address(0));
        (uint sharePrice, bool sharePriceTrusted) = vault.price();
        assertEq(sharePrice, 1e18); // $1
        assertEq(sharePriceTrusted, true);

        vm.roll(block.number + 6);

        PriceReader priceReader = PriceReader(platform.priceReader());
        (uint total, uint[] memory assetAmountPrice,,) = priceReader.getAssetsPrice(assets, amounts);
        assertEq(total, 30e18); // $30
        assertEq(assetAmountPrice[0], 10e18); // $10
        assertEq(assetAmountPrice[1], 20e18); // $20

        (uint tvl,) = vault.tvl();
        assertEq(tvl, 25e18); // $25

        uint[] memory amountsOnBalance = new uint[](2);
        amountsOnBalance[0] = tokenA.balanceOf(address(this));
        amountsOnBalance[1] = tokenB.balanceOf(address(this));
        (uint onBalanceUSD,,,) = priceReader.getAssetsPrice(assets, amountsOnBalance);
        assertEq(onBalanceUSD, 5e18); // %30 - $25 == $5

        // sharePrice is $1 after full withdraw
        uint balance = vault.balanceOf(address(this));
        vault.withdrawAssets(assets, balance, new uint[](2));
        (sharePrice,) = vault.price();
        assertEq(sharePrice, 1e18);
    }
}
