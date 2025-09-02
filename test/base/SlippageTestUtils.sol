// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console, Test} from "forge-std/Test.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Routines to test depositWithSlippage and withdrawWithSlippage of WrappedMetaVault
abstract contract SlippageTestUtils is Test {
    using SafeERC20 for IERC20;

    function _testDepositWithSlippage(
        address user,
        IWrappedMetaVault wrapper,
        uint amountToDeposit,
        IERC20 underlyingToken,
        uint tolerance
    ) internal {
        uint convertedShares = wrapper.convertToShares(amountToDeposit);
        uint previewedShares = wrapper.previewDeposit(amountToDeposit);

        uint balanceUnderlyingBefore = underlyingToken.balanceOf(user);
        uint balanceSharesBefore = wrapper.balanceOf(user);

        vm.startPrank(user);
        underlyingToken.forceApprove(address(wrapper), amountToDeposit);

        vm.expectRevert();
        wrapper.deposit(amountToDeposit, user, convertedShares + tolerance);

        uint mintedShares = wrapper.deposit(amountToDeposit, user, convertedShares - tolerance);
        vm.stopPrank();

        uint balanceUnderlyingAfter = underlyingToken.balanceOf(user);
        uint balanceSharesAfter = wrapper.balanceOf(user);

        assertEq(balanceUnderlyingAfter, balanceUnderlyingBefore - amountToDeposit, "Deposit is not EXACT_IN");
        assertEq(balanceSharesAfter, balanceSharesBefore + mintedShares, "Deposit minted shares do not match");
        assertApproxEqAbs(
            convertedShares, mintedShares, tolerance, "Convert and actual operation difference is higher than tolerance"
        );
        assertApproxEqAbs(
            previewedShares, mintedShares, tolerance, "Preview and actual operation difference is higher than tolerance"
        );

        // Mint _at least_ previewed shares.
        assertGe(mintedShares, previewedShares, "Minted shares is lower than converted minted");
    }

    function _testMintWithSlippage(
        address user,
        IWrappedMetaVault wrapper,
        uint amountToMint,
        IERC20 underlyingToken,
        uint tolerance
    ) internal {
        uint convertedUnderlying = wrapper.convertToAssets(amountToMint);
        uint previewedUnderlying = wrapper.previewMint(amountToMint);

        uint balanceUnderlyingBefore = underlyingToken.balanceOf(user);
        uint balanceSharesBefore = wrapper.balanceOf(user);

        vm.startPrank(user);
        underlyingToken.forceApprove(address(wrapper), previewedUnderlying);

        vm.expectRevert();
        wrapper.mint(amountToMint, user, convertedUnderlying - tolerance);

        uint depositedUnderlying = wrapper.mint(amountToMint, user, convertedUnderlying + tolerance);
        vm.stopPrank();

        uint balanceUnderlyingAfter = underlyingToken.balanceOf(user);
        uint balanceSharesAfter = wrapper.balanceOf(user);

        assertEq(balanceUnderlyingAfter, balanceUnderlyingBefore - depositedUnderlying, "Mint assets do not match");
        assertEq(balanceSharesAfter, balanceSharesBefore + amountToMint, "Mint is not EXACT_OUT");
        assertApproxEqAbs(
            convertedUnderlying,
            depositedUnderlying,
            tolerance,
            "Convert and actual operation difference is higher than tolerance"
        );
        assertApproxEqAbs(
            previewedUnderlying,
            depositedUnderlying,
            tolerance,
            "Preview and actual operation difference is higher than tolerance"
        );

        // Deposit _at most_ `previewedUnderlying`.
        assertGe(previewedUnderlying, depositedUnderlying, "Previewed underlying is lower than converted deposited");
    }

    function _testWithdrawWithSlippage(
        address user,
        IWrappedMetaVault wrapper,
        uint amountToWithdraw,
        IERC20 underlyingToken,
        uint tolerance
    ) internal {
        uint convertedShares = wrapper.convertToShares(amountToWithdraw);
        uint previewedShares = wrapper.previewWithdraw(amountToWithdraw);

        uint balanceUnderlyingBefore = underlyingToken.balanceOf(user);
        uint balanceSharesBefore = wrapper.balanceOf(user);

        vm.expectRevert();

        vm.prank(user);
        wrapper.withdraw(amountToWithdraw, user, user, convertedShares - tolerance);

        vm.prank(user);
        uint burnedShares = wrapper.withdraw(amountToWithdraw, user, user, convertedShares + tolerance);

        uint balanceUnderlyingAfter = underlyingToken.balanceOf(user);
        uint balanceSharesAfter = wrapper.balanceOf(user);

        assertEq(balanceUnderlyingAfter, balanceUnderlyingBefore + amountToWithdraw, "Withdraw is not EXACT_OUT");
        assertEq(balanceSharesAfter, balanceSharesBefore - burnedShares, "Withdraw burned shares do not match");
        assertApproxEqAbs(
            convertedShares, burnedShares, tolerance, "Convert and actual operation difference is higher than tolerance"
        );
        assertApproxEqAbs(
            previewedShares, burnedShares, tolerance, "Preview and actual operation difference is higher than tolerance"
        );

        // Burn _at most_ previewed shares.
        assertGe(previewedShares, burnedShares, "Previewed shares is lower than converted burned");
    }

    function _testRedeemWithSlippage(
        address user,
        IWrappedMetaVault wrapper,
        uint amountToRedeem,
        IERC20 underlyingToken,
        uint tolerance
    ) internal {
        uint convertedAssets = wrapper.convertToAssets(amountToRedeem);
        uint previewedAssets = wrapper.previewRedeem(amountToRedeem);

        uint balanceUnderlyingBefore = underlyingToken.balanceOf(user);
        uint balanceSharesBefore = wrapper.balanceOf(user);

        vm.startPrank(user);

        vm.expectRevert();
        wrapper.redeem(amountToRedeem, user, user, convertedAssets + tolerance);

        uint withdrawnAssets = wrapper.redeem(amountToRedeem, user, user, convertedAssets - tolerance);
        vm.stopPrank();

        uint balanceUnderlyingAfter = underlyingToken.balanceOf(user);
        uint balanceSharesAfter = wrapper.balanceOf(user);

        assertEq(balanceUnderlyingAfter, balanceUnderlyingBefore + withdrawnAssets, "Redeem is not EXACT_IN");
        assertEq(balanceSharesAfter, balanceSharesBefore - amountToRedeem, "Redeem burned shares do not match");
        assertApproxEqAbs(
            convertedAssets,
            withdrawnAssets,
            tolerance,
            "Convert and actual operation difference is higher than tolerance"
        );
        assertApproxEqAbs(
            previewedAssets,
            withdrawnAssets,
            tolerance,
            "Preview and actual operation difference is higher than tolerance"
        );

        // Withdraw _at least_ `previewedAssets`.
        assertGe(withdrawnAssets, previewedAssets, "Previewed assets is lower than converted withdrawn");
    }
}
