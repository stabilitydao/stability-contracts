// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {Proxy, IControllable} from "../../src/core/proxy/Proxy.sol";
import {MockStrategy} from "../../src/test/MockStrategy.sol";
import {MockAmmAdapter} from "../../src/test/MockAmmAdapter.sol";
import {FullMockSetup} from "../base/FullMockSetup.sol";
import {IVault, IStabilityVault} from "../../src/interfaces/IVault.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";

contract VaultTest is Test, FullMockSetup {
    CVault public vault;
    MockStrategy public strategyImplementation;
    MockStrategy public strategy;
    MockAmmAdapter public mockAmmAdapter;
    bool public canReceive;

    receive() external payable {
        require(canReceive);
    }

    function setUp() public {
        canReceive = true;
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

        assertEq(vault.name(), "Test vault");
        assertEq(vault.symbol(), "xVAULT");
        assertEq(vault.platform(), address(platform));
        assertEq(address(vault.strategy()), address(strategy));
        assertEq(strategy.strategyLogicId(), "Dev Alpha DeepSpaceSwap Farm");

        vault.setMaxSupply(1e20);

        assertEq(strategy.underlying(), address(lp));
        address[] memory assets = strategy.assets();
        assertEq(assets[0], address(tokenA));

        // cover MockStrategy
        strategy.ammAdapterId();
        strategy.setFees(0, 0);
        strategy.getRevenue();
        strategy.description();
        strategy.initVariants(address(0));
        strategy.isHardWorkOnDepositAllowed();
        strategy.isReadyForHardWork();

        // cover StrategyBase
        address[] memory assets_ = new address[](1);
        assets_[0] = strategy.underlying();
        uint[] memory amountsMax = new uint[](2);
        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        strategy.previewDepositAssets(assets_, amountsMax);
    }

    function testDepositWithdrawHardWork() public {
        _initAll();

        address[] memory assets = new address[](2);
        assets[0] = address(tokenA);
        assets[1] = address(tokenB);

        uint[] memory amounts = new uint[](2);
        amounts[0] = 10e18;
        amounts[1] = 10e6;

        tokenA.mint(amounts[0] * 2);
        tokenB.mint(amounts[1] * 2);
        lp.mint(1e18);

        tokenA.approve(address(vault), amounts[0] * 2);
        tokenB.approve(address(vault), amounts[1] * 2);
        lp.approve(address(vault), 1e18);

        (uint[] memory amountsConsumed, uint sharesOut,) = vault.previewDepositAssets(assets, amounts);
        assertGt(amountsConsumed[0], 0);
        assertGt(amountsConsumed[1], 0);

        (uint[] memory amountsConsumedWrite,,) = vault.previewDepositAssets(assets, amounts);
        assertEq(amountsConsumedWrite[0], amountsConsumed[0]);
        assertEq(amountsConsumedWrite[1], amountsConsumed[1]);

        // check with other proportions
        uint[] memory otherAmounts = new uint[](2);
        otherAmounts[0] = 10e18;
        otherAmounts[1] = 10e36;
        (amountsConsumed,,) = vault.previewDepositAssets(assets, otherAmounts);
        assertGt(amountsConsumed[0], 0);
        assertGt(amountsConsumed[1], 0);

        vm.expectRevert(abi.encodeWithSelector(IFactory.NotActiveVault.selector));
        vault.depositAssets(assets, amounts, 0, address(0));

        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);
        uint[] memory statuses = new uint[](1);
        statuses[0] = 1;
        factory.setVaultStatus(vaults, statuses);

        amounts = new uint[](3);
        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        vault.depositAssets(assets, amounts, 0, address(0));
        amounts = new uint[](2);

        amounts[0] = 1e12;
        amounts[1] = 1e4;
        vm.expectRevert(abi.encodeWithSelector(IVault.NotEnoughAmountToInitSupply.selector, 5e12, 1e19));
        vault.depositAssets(assets, amounts, 0, address(0));
        amounts[0] = 10e18;
        amounts[1] = 10e6;

        strategy.toggleDepositReturnZero();
        vm.expectRevert(abi.encodeWithSelector(IVault.StrategyZeroDeposit.selector));
        vault.depositAssets(assets, amounts, 0, address(0));
        strategy.toggleDepositReturnZero();

        vault.depositAssets(assets, amounts, 0, address(0));

        vm.roll(block.number + 5);

        uint shares = vault.balanceOf(address(this));
        assertGt(shares, 0);
        assertEq(shares, sharesOut);

        vm.expectRevert(abi.encodeWithSelector(IStabilityVault.WaitAFewBlocks.selector));
        vault.withdrawAssets(assets, shares / 2, new uint[](2));

        // underlying token deposit
        address[] memory underlyingAssets = new address[](1);
        underlyingAssets[0] = address(lp);
        otherAmounts = new uint[](1);
        otherAmounts[0] = 1e16;
        vault.depositAssets(underlyingAssets, otherAmounts, 0, address(0));
        shares = vault.balanceOf(address(this));

        vm.roll(block.number + 6);

        // initial shares
        assertLt(shares, vault.totalSupply());

        vm.txGasPrice(15e10); // 150gwei
        vm.expectRevert(abi.encodeWithSelector(IVault.NotEnoughBalanceToPay.selector));
        vault.doHardWork();

        vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectMsgSender.selector));
        vm.prank(address(666));
        vault.doHardWork();

        (bool success,) = payable(address(vault)).call{value: 5e17}("");
        assertEq(success, true);

        canReceive = false;
        vm.expectRevert(abi.encodeWithSelector(IControllable.ETHTransferFailed.selector));
        vault.doHardWork();
        canReceive = true;

        vault.doHardWork();

        otherAmounts[0] = 0;
        vault.withdrawAssets(underlyingAssets, 1e16, otherAmounts);

        vm.roll(block.number + 6);

        shares = vault.balanceOf(address(this));

        console.log("totalSupply", vault.totalSupply());
        console.log("balance", IERC20(vault.strategy().underlying()).balanceOf(address(strategy)));
        console.log("strategy.totalSupply", IERC20(vault.strategy().underlying()).totalSupply());
        console.log("strategy.total", vault.strategy().total());
        console.log("shares", shares);
        console.log("vault.totalSupply", vault.totalSupply());
        vm.prank(address(100));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(100), 0, shares / 2)
        );
        vault.withdrawAssets(assets, shares / 2, new uint[](2), address(this), address(this));

        vm.expectRevert(IControllable.IncorrectZeroArgument.selector);
        vault.withdrawAssets(assets, 0, new uint[](2));

        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        vault.withdrawAssets(assets, shares / 2, new uint[](3));

        vm.expectRevert(IVault.NotEnoughBalanceToPay.selector);
        vault.withdrawAssets(assets, shares * 10, new uint[](2));

        uint[] memory minOuts = new uint[](2);
        minOuts[0] = 1e30;
        minOuts[1] = 0;
        vm.expectRevert(
            abi.encodeWithSelector(IVault.ExceedSlippageExactAsset.selector, assets[0], 2498000000500000000, 1e30)
        );
        vault.withdrawAssets(assets, shares / 2, minOuts);

        vault.withdrawAssets(assets, shares / 2, new uint[](2));
        vm.roll(block.number + 6);
        vault.withdrawAssets(assets, shares - shares / 2, new uint[](2));

        assertEq(vault.balanceOf(address(this)), 0, "Withdrawn not all");

        vault.setDoHardWorkOnDeposit(false);
        assertEq(vault.doHardWorkOnDeposit(), false);
        vault.setDoHardWorkOnDeposit(true);
        assertEq(vault.doHardWorkOnDeposit(), true);

        assertEq(vault.maxSupply(), 0);

        amounts = new uint[](2);
        amounts[0] = 10e18;
        amounts[1] = 10e6;

        vm.expectRevert();
        vault.depositAssets(assets, amounts, 1e30, address(0));

        vault.setMaxSupply(1e3);
        vm.expectRevert();
        vault.depositAssets(assets, amounts, 0, address(0));
    }

    function testFuse() public {
        _initAll();

        address[] memory assets = new address[](2);
        assets[0] = address(tokenA);
        assets[1] = address(tokenB);

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

        vm.expectRevert(abi.encodeWithSelector(IFactory.NotActiveVault.selector));
        vault.depositAssets(assets, amounts, 0, address(0));
        vm.expectRevert(abi.encodeWithSelector(IFactory.NotActiveVault.selector));
        vault.depositAssets(underlyingAssets, otherAmounts, 0, address(0));

        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);
        uint[] memory statuses = new uint[](1);
        statuses[0] = 1;
        factory.setVaultStatus(vaults, statuses);
        vault.depositAssets(assets, amounts, 0, address(0));
        vault.depositAssets(underlyingAssets, otherAmounts, 0, address(0));
        uint shares = vault.balanceOf(address(this));
        assertGt(shares, 0);

        vm.roll(block.number + 6);

        // initial shares
        assertLt(shares, vault.totalSupply());

        strategy.triggerFuse();

        vm.expectRevert(IVault.FuseTrigger.selector);
        vault.depositAssets(assets, amounts, 0, address(0));

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

    function testChageNameSymbol() public {
        _initAll();

        string memory newName = "New vault name";
        string memory newSymbol = "New vault symbol";
        vault.setName(newName);
        assertEq(vault.name(), newName);

        vault.setSymbol(newSymbol);
        assertEq(vault.symbol(), newSymbol);
    }

    function _initAll() internal {
        vm.expectRevert(IControllable.IncorrectInitParams.selector);
        vault.initialize(
            IVault.VaultInitializationData({
                platform: address(platform),
                strategy: address(strategy),
                name: "Test vault",
                symbol: "xVAULT",
                tokenId: 0,
                vaultInitAddresses: new address[](1),
                vaultInitNums: new uint[](0)
            })
        );

        vault.initialize(
            IVault.VaultInitializationData({
                platform: address(platform),
                strategy: address(strategy),
                name: "Test vault",
                symbol: "xVAULT",
                tokenId: 0,
                vaultInitAddresses: new address[](0),
                vaultInitNums: new uint[](0)
            })
        );

        address[] memory addresses = new address[](5);
        addresses[0] = address(platform);
        addresses[1] = address(vault);
        addresses[2] = address(mockAmmAdapter);
        addresses[3] = address(lp);
        addresses[4] = address(tokenA);

        strategy.initialize(addresses, new uint[](0), new int24[](0));
    }
}
