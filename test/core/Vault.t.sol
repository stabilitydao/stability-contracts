// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import "../../src/core/vaults/CVault.sol";
import "../../src/core/proxy/Proxy.sol";
import "../../src/strategies/libs/StrategyIdLib.sol";
import "../../src/test/MockStrategy.sol";
import "../../src/test/MockAmmAdapter.sol";
import "../base/FullMockSetup.sol";

contract VaultTest is Test, FullMockSetup {
    CVault public vault;
    MockStrategy public strategyImplementation;
    MockStrategy public strategy;
    MockAmmAdapter public mockAmmAdapter;

    receive() external payable {}

    function setUp() public {
        strategyImplementation = new MockStrategy();

        Proxy vaultProxy = new Proxy();
        Proxy strategyProxy = new Proxy();

        vaultProxy.initProxy(address(vaultImplementation));
        strategyProxy.initProxy(address(strategyImplementation));

        vault = CVault(payable(address(vaultProxy)));
        strategy = MockStrategy(address(strategyProxy));

        mockAmmAdapter = new MockAmmAdapter(address(tokenA), address(tokenB));
    }

    function testSetup() public {
        _initAll();

        assertEq(vault.name(), 'Test vault');
        assertEq(vault.symbol(), 'xVAULT');
        assertEq(vault.platform(), address(platform));
        assertEq(address(vault.strategy()), address(strategy));
        assertEq(strategy.STRATEGY_LOGIC_ID(), "Dev Alpha DeepSpaceSwap Farm");

        vault.setMaxSupply(1e20);

        assertEq(strategy.underlying(), address(lp));
        address[] memory assets = strategy.assets();
        assertEq(assets[0], address(tokenA));
    }

    function testDepositWithdrawHardWork() public {
        _initAll();

        address[] memory assets = new address[](2);
        assets[0] = address (tokenA);
        assets[1] = address (tokenB);

        uint[] memory amounts = new uint[](2);
        amounts[0] = 10e18;
        amounts[1] = 10e6;

        tokenA.mint(amounts[0]);
        tokenB.mint(amounts[1]);
        lp.mint(1e18);

        tokenA.approve(address(vault), amounts[0]);
        tokenB.approve(address(vault), amounts[1]);
        lp.approve(address(vault), 1e18);

        (uint[] memory amountsConsumed, uint sharesOut,) = vault.previewDepositAssets(assets, amounts);
        assertGt(amountsConsumed[0], 0);
        assertGt(amountsConsumed[1], 0);

        // check with other proportions
        uint[] memory otherAmounts = new uint[](2);
        otherAmounts[0] = 10e18;
        otherAmounts[1] = 10e36;
        (amountsConsumed,,) = vault.previewDepositAssets(assets, otherAmounts);
        assertGt(amountsConsumed[0], 0);
        assertGt(amountsConsumed[1], 0);

        vault.depositAssets(assets, amounts, 0);

        vm.roll(block.number + 5);

        uint shares = vault.balanceOf(address(this));
        assertGt(shares, 0);
        assertEq(shares, sharesOut);

        vm.expectRevert("Vault: wait few blocks");
        vault.withdrawAssets(assets, shares / 2, new uint[](2));

        // underlying token deposit
        address[] memory underlyingAssets = new address[](1);
        underlyingAssets[0] = address(lp);
        otherAmounts = new uint[](1);
        otherAmounts[0] = 1e16;
        vault.depositAssets(underlyingAssets, otherAmounts, 0);
        shares = vault.balanceOf(address(this));

        vm.roll(block.number + 6);

        // initial shares
        assertLt(shares, vault.totalSupply());

        vm.txGasPrice(15e10); // 150gwei
        vm.expectRevert("Vault: not enough balance to pay gas");
        vault.doHardWork();

        (bool success, ) = payable(address(vault)).call{value: 5e17}("");
        assertEq(success, true);

        vault.doHardWork();

        otherAmounts[0] = 0;
        vault.withdrawAssets(underlyingAssets, 1e16, otherAmounts);

        vm.roll(block.number + 6);

        shares = vault.balanceOf(address(this));
        vault.withdrawAssets(assets, shares / 2, new uint[](2));

        vm.roll(block.number + 6);

        vault.withdrawAssets(assets, shares - shares / 2, new uint[](2));

        assertEq(vault.balanceOf(address(this)), 0);

        vault.setDoHardWorkOnDeposit(false);
        assertEq(vault.doHardWorkOnDeposit(), false);
        vault.setDoHardWorkOnDeposit(true);
        assertEq(vault.doHardWorkOnDeposit(), true);
    }

    function testFuse() public {
        _initAll();

        address[] memory assets = new address[](2);
        assets[0] = address (tokenA);
        assets[1] = address (tokenB);

        uint[] memory amounts = new uint[](2);
        amounts[0] = 10e18;
        amounts[1] = 10e6;

        address[] memory underlyingAssets = new address[](1);
        underlyingAssets[0] = address(lp);
        uint[] memory otherAmounts = new uint[](1);
        otherAmounts[0] = 1e16;

        tokenA.mint(amounts[0]);
        tokenB.mint(amounts[1]);
        lp.mint(1e18);

        tokenA.approve(address(vault), amounts[0]);
        tokenB.approve(address(vault), amounts[1]);
        lp.approve(address(vault), 1e18);

        vault.depositAssets(assets, amounts, 0);
        vault.depositAssets(underlyingAssets, otherAmounts, 0);
        uint shares = vault.balanceOf(address(this));
        assertGt(shares, 0);

        vm.roll(block.number + 6);

        // initial shares
        assertLt(shares, vault.totalSupply());

        strategy.triggerFuse();

        otherAmounts[0] = 0;
        vault.withdrawAssets(underlyingAssets, 1e16, otherAmounts);

        vm.roll(block.number + 6);

        shares = vault.balanceOf(address(this));
        vault.withdrawAssets(assets, shares / 2, new uint[](2));

        vm.roll(block.number + 6);

        vault.withdrawAssets(assets, shares - shares / 2, new uint[](2));

        assertEq(vault.balanceOf(address(this)), 0);

        vault.doHardWork();
    }

    function _initAll() internal {
        vault.initialize(
            address(platform),
            address(strategy),
            'Test vault',
            'xVAULT',
            0,
            new address[](0),
            new uint[](0)
        );

        address[] memory addresses = new address[](5);
        addresses[0] = address(platform);
        addresses[1] = address(vault);
        addresses[2] = address(mockAmmAdapter);
        addresses[3] = address(lp);
        addresses[4] = address(tokenA);

        strategy.initialize(
            addresses,
            new uint[](0),
            new int24[](0)
        );

    }
}
