// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {PendleERC4626WithAdapterSY} from "../../src/integrations/pendle/PendleERC4626WithAdapterSYFlatten.sol";
import {PendleWrappedMetaVaultAdapter} from "../../src/periphery/PendleWrappedMetaVaultAdapter.sol";
import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
// import {console} from "forge-std/Test.sol";

contract PendleWrappedMetaVaultAdapterTest is SonicSetup {
    address internal multisig;

    constructor() {
        vm.rollFork(38601318); // Jul-15-2025 12:18:16 PM +UTC
        multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_META_USD);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_META_S);
    }

    function testForMetaUsd100() public {
        _testForMetaUsd(100e6);
    }

    function testForMetaUsd1e6() public {
        _testForMetaUsd(1_000_000e6);
    }

    function testForMetaS100() public {
        _testForMetaS(100e18);
    }

    function testForMetaS1e6() public {
        _testForMetaS(1_000_000e18);
    }

    function _testForMetaUsd(uint amount) internal {
        // -------------------- setup SY, SY-adapter and MetaVault
        (PendleERC4626WithAdapterSY syMetaUsd, PendleWrappedMetaVaultAdapter adapter) =
            _setUp(SonicConstantsLib.WRAPPED_METAVAULT_META_USD, SonicConstantsLib.METAVAULT_META_USD);

        // -------------------- deposit to SY
        _dealAndApproveSingle(address(this), address(syMetaUsd), SonicConstantsLib.TOKEN_USDC, amount);
        {
            uint shares = syMetaUsd.previewDeposit(SonicConstantsLib.TOKEN_USDC, amount);
            uint amountSharesOut =
                syMetaUsd.deposit(address(this), SonicConstantsLib.TOKEN_USDC, amount, shares * 999 / 1000);

            assertEq(
                IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this)),
                0,
                "USDC balance should be zero after deposit"
            );

            assertEq(syMetaUsd.balanceOf(address(this)), amountSharesOut, "SY balance should be expected");
        }

        // -------------------- user is not able to deposit / withdraw without waiting
        _tryToDepositToSY(address(this), syMetaUsd, SonicConstantsLib.TOKEN_USDC, amount, true); // the user cannot deposit
        _tryToDepositToSY(address(2), syMetaUsd, SonicConstantsLib.TOKEN_USDC, amount, true); // the other user cannot deposit too
        _tryToRedeemFromSY(syMetaUsd, SonicConstantsLib.TOKEN_USDC, amount, true);

        // -------------------- wait a few blocks
        vm.roll(block.number + 6);

        // -------------------- withdraw half from SY
        uint balance = syMetaUsd.balanceOf(address(this));
        assertNotEq(balance, 0, "Balance should not be zero 1");

        syMetaUsd.redeem(address(this), balance / 2, SonicConstantsLib.TOKEN_USDC, amount * 99 / 100 / 2, false);

        assertApproxEqAbs(
            IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this)),
            amount / 2,
            amount / 2 / 1000,
            "USDC balance mismatch 1"
        );

        // -------------------- user IS ABLE to deposit without waiting
        // if we need to disable deposit after withdraw we need our own SY implementation or invent smth on wmetaUSD side
        _tryToDepositToSY(address(this), syMetaUsd, SonicConstantsLib.TOKEN_USDC, amount, false);
        _tryToDepositToSY(address(2), syMetaUsd, SonicConstantsLib.TOKEN_USDC, amount, false);

        // -------------------- user is not able to withdraw without waiting
        _tryToRedeemFromSY(syMetaUsd, SonicConstantsLib.TOKEN_USDC, amount, true);

        // -------------------- wait a few blocks
        vm.roll(block.number + 6);

        // -------------------- withdraw all from SY
        balance = syMetaUsd.balanceOf(address(this));
        uint previewAmount = syMetaUsd.previewRedeem(SonicConstantsLib.TOKEN_USDC, balance);
        assertNotEq(balance, 0, "Balance should not be zero 2");

        uint balanceUsdcBeforeRedeem = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this));
        uint redeemed =
            syMetaUsd.redeem(address(this), balance, SonicConstantsLib.TOKEN_USDC, amount * 99 / 100 / 2, false);

        assertApproxEqAbs(
            IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this)),
            amount,
            amount / 1000,
            "USDC balance mismatch 2"
        );

        assertEq(syMetaUsd.balanceOf(address(this)), 0, "Balance should be zero");
        assertApproxEqAbs(previewAmount, redeemed, 1, "Preview amount should be equal to redeemed amount");
        assertApproxEqAbs(
            IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this)) - balanceUsdcBeforeRedeem,
            previewAmount,
            1,
            "User should withdraw expected previewed amount"
        );

        // -------------------- check zero balances
        assertEq(
            IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(adapter)), 0, "Adapter USDC balance should be zero"
        );
        assertEq(
            IERC20(SonicConstantsLib.WRAPPED_METAVAULT_META_USD).balanceOf(address(adapter)),
            0,
            "Adapter wmetaUSD balance should be zero"
        );
        assertApproxEqAbs(
            IERC20(SonicConstantsLib.METAVAULT_META_USD).balanceOf(address(adapter)),
            0,
            1, // rounding issue on metaUsd side
            "Adapter metaUSD balance should be zero"
        );

        assertEq(
            IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(syMetaUsd)), 0, "SY USDC balance should be zero"
        );
        assertEq(
            IERC20(SonicConstantsLib.WRAPPED_METAVAULT_META_USD).balanceOf(address(syMetaUsd)),
            0,
            "SY wmetaUSD balance should be zero"
        );
        assertApproxEqAbs(
            IERC20(SonicConstantsLib.METAVAULT_META_USD).balanceOf(address(syMetaUsd)),
            0,
            1, // rounding issue on metaUsd side
            "SY metaUSD balance should be zero"
        );
    }

    function _testForMetaS(uint amount) internal {
        // -------------------- setup SY, SY-adapter and MetaVault
        (PendleERC4626WithAdapterSY syMetaS, PendleWrappedMetaVaultAdapter adapter) =
            _setUp(SonicConstantsLib.WRAPPED_METAVAULT_META_S, SonicConstantsLib.METAVAULT_META_S);

        // -------------------- deposit to SY
        _dealAndApproveSingle(address(this), address(syMetaS), SonicConstantsLib.TOKEN_WS, amount);
        {
            uint shares = syMetaS.previewDeposit(SonicConstantsLib.TOKEN_WS, amount);
            uint amountSharesOut =
                syMetaS.deposit(address(this), SonicConstantsLib.TOKEN_WS, amount, shares * 999 / 1000);

            assertEq(
                IERC20(SonicConstantsLib.TOKEN_WS).balanceOf(address(this)),
                0,
                "wS balance should be zero after deposit"
            );

            assertEq(syMetaS.balanceOf(address(this)), amountSharesOut, "SY balance should be expected");
        }

        // -------------------- user is not able to deposit / withdraw without waiting
        _tryToDepositToSY(address(this), syMetaS, SonicConstantsLib.TOKEN_WS, amount, true); // the user cannot deposit
        _tryToDepositToSY(address(2), syMetaS, SonicConstantsLib.TOKEN_WS, amount, true); // the other user cannot deposit too
        _tryToRedeemFromSY(syMetaS, SonicConstantsLib.TOKEN_WS, amount, true);

        // -------------------- wait a few blocks
        vm.roll(block.number + 6);

        // -------------------- withdraw half from SY
        uint balance = syMetaS.balanceOf(address(this));
        assertNotEq(balance, 0, "Balance should not be zero 1");

        syMetaS.redeem(address(this), balance / 2, SonicConstantsLib.TOKEN_WS, amount * 99 / 100 / 2, false);

        assertApproxEqAbs(
            IERC20(SonicConstantsLib.TOKEN_WS).balanceOf(address(this)),
            amount / 2,
            amount / 2 / 1000,
            "wS balance mismatch 1"
        );

        // -------------------- user IS ABLE to deposit without waiting
        // if we need to disable deposit after withdraw we need our own SY implementation or invent smth on wmetaUSD side
        _tryToDepositToSY(address(this), syMetaS, SonicConstantsLib.TOKEN_WS, amount, false);
        _tryToDepositToSY(address(2), syMetaS, SonicConstantsLib.TOKEN_WS, amount, false);

        // -------------------- user is not able to withdraw without waiting
        _tryToRedeemFromSY(syMetaS, SonicConstantsLib.TOKEN_WS, amount, true);

        // -------------------- wait a few blocks
        vm.roll(block.number + 6);

        // -------------------- withdraw all from SY
        balance = syMetaS.balanceOf(address(this));
        uint previewAmount = syMetaS.previewRedeem(SonicConstantsLib.TOKEN_WS, balance);
        assertNotEq(balance, 0, "Balance should not be zero 2");

        uint balanceAssetBeforeRedeem = IERC20(SonicConstantsLib.TOKEN_WS).balanceOf(address(this));
        uint redeemed = syMetaS.redeem(address(this), balance, SonicConstantsLib.TOKEN_WS, amount * 99 / 100 / 2, false);

        assertApproxEqAbs(
            IERC20(SonicConstantsLib.TOKEN_WS).balanceOf(address(this)), amount, amount / 1000, "wS balance mismatch 2"
        );

        assertEq(syMetaS.balanceOf(address(this)), 0, "Balance should be zero");
        assertApproxEqAbs(
            previewAmount, redeemed, previewAmount / 1e8, "Preview amount should be equal to redeemed amount 1"
        );
        assertApproxEqAbs(
            IERC20(SonicConstantsLib.TOKEN_WS).balanceOf(address(this)) - balanceAssetBeforeRedeem,
            previewAmount,
            previewAmount / 1e8,
            "User should withdraw expected previewed amount 1"
        );

        // -------------------- check zero balances
        assertEq(IERC20(SonicConstantsLib.TOKEN_WS).balanceOf(address(adapter)), 0, "Adapter wS balance should be zero");
        assertEq(
            IERC20(SonicConstantsLib.WRAPPED_METAVAULT_META_S).balanceOf(address(adapter)),
            0,
            "Adapter wmetaS balance should be zero"
        );
        assertApproxEqAbs(
            IERC20(SonicConstantsLib.METAVAULT_META_S).balanceOf(address(adapter)),
            0,
            1, // rounding issue on metaS side
            "Adapter metaS balance should be zero"
        );

        assertEq(IERC20(SonicConstantsLib.TOKEN_WS).balanceOf(address(syMetaS)), 0, "SY wS balance should be zero");
        assertEq(
            IERC20(SonicConstantsLib.WRAPPED_METAVAULT_META_S).balanceOf(address(syMetaS)),
            0,
            "SY wmetaS balance should be zero"
        );
        assertApproxEqAbs(
            IERC20(SonicConstantsLib.METAVAULT_META_S).balanceOf(address(syMetaS)),
            0,
            1, // rounding issue on metaS side
            "SY metaS balance should be zero"
        );
    }

    function testSalvage() public {
        address receiver = makeAddr("receiver");
        (, PendleWrappedMetaVaultAdapter adapter) =
            _setUp(SonicConstantsLib.WRAPPED_METAVAULT_META_USD, SonicConstantsLib.METAVAULT_META_USD);
        _dealAndApproveSingle(address(adapter), address(this), SonicConstantsLib.TOKEN_USDC, 100e6);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.NotOwner.selector);
        vm.prank(receiver);
        adapter.salvage(SonicConstantsLib.TOKEN_USDC, receiver, 100e6);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.ZeroAddress.selector);
        vm.prank(address(this));
        adapter.salvage(SonicConstantsLib.TOKEN_USDC, address(0), 100e6);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.ZeroAddress.selector);
        vm.prank(address(this));
        adapter.salvage(address(0), receiver, 100e6);

        vm.prank(address(this));
        adapter.salvage(SonicConstantsLib.TOKEN_USDC, receiver, 100e6);
    }

    function testBadPathNotWhitelistedSy() public {
        address asset = SonicConstantsLib.TOKEN_USDC;
        uint amount = 100e6;

        // -------------------- setup SY, SY-adapter and MetaVault
        (PendleERC4626WithAdapterSY syMetaUsd, PendleWrappedMetaVaultAdapter adapter) =
            _setUp(SonicConstantsLib.WRAPPED_METAVAULT_META_USD, SonicConstantsLib.METAVAULT_META_USD);
        _dealAndApproveSingle(address(this), address(syMetaUsd), asset, amount);

        // -------------------- deposit to SY
        vm.prank(address(this));
        adapter.changeWhitelist(address(syMetaUsd), false);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.NotWhitelisted.selector);
        syMetaUsd.deposit(address(this), asset, amount, 0);

        vm.prank(address(this));
        adapter.changeWhitelist(address(syMetaUsd), true);

        syMetaUsd.deposit(address(this), asset, amount, 0);
        vm.roll(block.number + 6);

        // -------------------- withdraw all from SY
        uint balance = syMetaUsd.balanceOf(address(this));

        vm.prank(address(this));
        adapter.changeWhitelist(address(syMetaUsd), false);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.NotWhitelisted.selector);
        syMetaUsd.redeem(address(this), balance, asset, 0, false);

        vm.prank(address(this));
        adapter.changeWhitelist(address(syMetaUsd), true);

        syMetaUsd.redeem(address(this), balance, asset, 0, false);
    }

    function testBadPathIncorrectTokens() public {
        address asset = SonicConstantsLib.TOKEN_USDC;
        uint amount = 100e6;

        // -------------------- setup SY, SY-adapter and MetaVault
        (PendleERC4626WithAdapterSY syMetaUsd, PendleWrappedMetaVaultAdapter adapter) =
            _setUp(SonicConstantsLib.WRAPPED_METAVAULT_META_USD, SonicConstantsLib.METAVAULT_META_USD);
        _dealAndApproveSingle(address(this), address(syMetaUsd), asset, amount);
        _dealAndApproveSingle(address(this), address(syMetaUsd), SonicConstantsLib.TOKEN_WS, amount);

        // -------------------- deposit to SY
        vm.expectRevert(PendleWrappedMetaVaultAdapter.IncorrectToken.selector);
        vm.prank(address(syMetaUsd));
        adapter.convertToDeposit(SonicConstantsLib.TOKEN_WS, amount);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.IncorrectToken.selector);
        adapter.previewConvertToRedeem(SonicConstantsLib.TOKEN_WS, amount);

        syMetaUsd.deposit(address(this), asset, amount, 0);
        vm.roll(block.number + 6);

        // -------------------- withdraw all from SY
        uint balance = syMetaUsd.balanceOf(address(this));

        vm.expectRevert(PendleWrappedMetaVaultAdapter.IncorrectToken.selector);
        vm.prank(address(syMetaUsd));
        adapter.convertToRedeem(SonicConstantsLib.TOKEN_WS, amount);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.IncorrectToken.selector);
        adapter.previewConvertToDeposit(SonicConstantsLib.TOKEN_WS, amount);

        syMetaUsd.redeem(address(this), balance, asset, 0, false);
    }

    function testBadPathsChangeWhitelist() public {
        (PendleERC4626WithAdapterSY syMetaUsd, PendleWrappedMetaVaultAdapter adapter) =
            _setUp(SonicConstantsLib.WRAPPED_METAVAULT_META_USD, SonicConstantsLib.METAVAULT_META_USD);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.NotOwner.selector);
        vm.prank(address(314));
        adapter.changeWhitelist(address(syMetaUsd), true);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.ZeroAddress.selector);
        vm.prank(address(this));
        adapter.changeWhitelist(address(0), false);

        vm.prank(address(this));
        adapter.changeWhitelist(address(syMetaUsd), true);
        assertEq(adapter.whitelisted(address(syMetaUsd)), true);

        address newOwner = makeAddr("newOwner");

        vm.expectRevert(PendleWrappedMetaVaultAdapter.NotOwner.selector);
        vm.prank(newOwner);
        adapter.changeOwner(newOwner);

        assertEq(adapter.owner(), address(this));
        vm.prank(address(this));
        adapter.changeOwner(newOwner);
        assertEq(adapter.owner(), newOwner);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.NotOwner.selector);
        vm.prank(address(this));
        adapter.changeWhitelist(address(syMetaUsd), false);

        vm.prank(newOwner);
        adapter.changeWhitelist(address(syMetaUsd), false);

        assertEq(adapter.whitelisted(address(syMetaUsd)), false);
    }

    function testBadPathsConstructor() public {
        vm.expectRevert(PendleWrappedMetaVaultAdapter.ZeroAddress.selector);
        new PendleWrappedMetaVaultAdapter(address(0));
    }

    //region ---------------------------------------- Internal logic
    function _setUp(
        address wrappedMetaVault_,
        address metaVault_
    ) internal returns (PendleERC4626WithAdapterSY syMetaUsd, PendleWrappedMetaVaultAdapter adapter) {
        adapter = new PendleWrappedMetaVaultAdapter(metaVault_);
        syMetaUsd = new PendleERC4626WithAdapterSY(wrappedMetaVault_, address(adapter));

        vm.prank(multisig);
        IMetaVault(metaVault_).changeWhitelist(address(adapter), true);

        vm.prank(address(this));
        adapter.changeWhitelist(address(syMetaUsd), true);

        {
            address owner = syMetaUsd.owner();
            vm.prank(owner);
            syMetaUsd.setAdapter(address(adapter));
        }
    }

    function _tryToDepositDirectly(IMetaVault metaVault, uint amount, bool shouldRevert) internal {
        uint snapshot = vm.snapshotState();

        _dealAndApproveSingle(address(this), address(metaVault), SonicConstantsLib.TOKEN_USDC, amount);
        address[] memory assets = metaVault.assetsForDeposit();
        uint[] memory amountsMax = new uint[](1);
        amountsMax[0] = amount;

        if (shouldRevert) {
            vm.expectRevert();
        }
        metaVault.depositAssets(assets, amountsMax, 0, address(this));

        vm.revertToState(snapshot);
    }

    function _tryToDepositToSY(
        address user,
        PendleERC4626WithAdapterSY sy_,
        address asset_,
        uint amount,
        bool shouldRevert
    ) internal {
        uint snapshot = vm.snapshotState();

        _dealAndApproveSingle(user, address(sy_), asset_, amount);
        uint shares = sy_.previewDeposit(asset_, amount);

        vm.prank(user);
        if (shouldRevert) {
            vm.expectRevert(IStabilityVault.WaitAFewBlocks.selector);
        }
        sy_.deposit(user, asset_, amount, shares * 999 / 1000);

        vm.revertToState(snapshot);
    }

    function _tryToRedeemFromSY(
        PendleERC4626WithAdapterSY sy_,
        address asset_,
        uint expectedAmount,
        bool shouldRevert
    ) internal {
        uint snapshot = vm.snapshotState();

        uint balance = sy_.balanceOf(address(this));

        if (shouldRevert) {
            vm.expectRevert(IStabilityVault.WaitAFewBlocks.selector);
        }
        sy_.redeem(address(this), balance, asset_, expectedAmount * 99 / 100, false);

        vm.revertToState(snapshot);
    }

    //endregion ---------------------------------------- Internal logic

    //region ---------------------------------------- Helpers
    function _dealAndApproveSingle(address user, address spender, address asset, uint amount) internal {
        deal(asset, user, amount);

        vm.prank(user);
        IERC20(asset).approve(spender, amount);
    }

    function _upgradeMetaVault(address metaVault_) internal {
        IMetaVaultFactory metaVaultFactory = IMetaVaultFactory(IPlatform(SonicConstantsLib.PLATFORM).metaVaultFactory());

        // Upgrade MetaVault to the new implementation
        address vaultImplementation = address(new MetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);
        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault_);
        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);
    }
    //endregion ---------------------------------------- Helpers
}
