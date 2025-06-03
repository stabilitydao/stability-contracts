// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPermit2} from "../../src/integrations/permit2/IPermit2.sol";
import {ISilo} from "../../src/integrations/silo/ISilo.sol";

abstract contract ERC4626UniversalTest is Test {
    using SafeERC20 for IERC20;

    address public multisig;

    // Variables to be defined by setUpForkTestVariables().
    string internal network;
    // Use overrideBlockNumber to specify a block number in a specific test.
    uint internal overrideBlockNumber;
    IERC4626 internal wrapper;
    address internal underlyingDonor;
    uint internal amountToDonate;

    // blockNumber is used by the base test. To override it, please use overrideBlockNumber.
    uint internal blockNumber;

    IPermit2 internal permit2;

    // Some tokens have specific minimum deposit requirements, and need to override this default value.
    uint internal minDeposit = 100;
    // Tolerance between convert/preview and the actual operation.
    uint internal constant TOLERANCE = 2;

    IERC20 internal underlyingToken;
    uint internal underlyingToWrappedFactor;

    address internal alice;
    address internal lp;
    address internal user;
    uint internal userInitialUnderlying;
    uint internal userInitialShares;

    function setUp() public virtual {
        setUpForkTestVariables();
        blockNumber = overrideBlockNumber != 0 ? overrideBlockNumber : 3842500;
        vm.label(address(wrapper), "wrapper");

        vm.createSelectFork(network, blockNumber);

        _upgradeThings();

        underlyingToken = IERC20(wrapper.asset());
        vm.label(address(underlyingToken), "underlying");

        if (underlyingToken.balanceOf(underlyingDonor) < 3 * amountToDonate) {
            revert("Underlying donor does not have enough liquidity. Check Readme.md, chapter `Debug failing tests`.");
        }

        underlyingToWrappedFactor = 10 ** (wrapper.decimals() - IERC20Metadata(address(underlyingToken)).decimals());

        (user,) = makeAddrAndKey("User");
        vm.label(user, "User");
        _initializeWallet(user);

        userInitialUnderlying = underlyingToken.balanceOf(user);
        userInitialShares = wrapper.balanceOf(user);

        (lp,) = makeAddrAndKey("lp");
        vm.label(lp, "lp");
        _initializeWallet(lp);
        _setupAllowance(lp);

        (alice,) = makeAddrAndKey("Alice");
        vm.label(alice, "Alice");
        _initializeWallet(alice);
        _setupAllowance(alice);
    }

    function testDeposit__Fork__Fuzz(uint amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, minDeposit, userInitialUnderlying);

        uint convertedShares = wrapper.convertToShares(amountToDeposit);
        uint previewedShares = wrapper.previewDeposit(amountToDeposit);

        uint balanceUnderlyingBefore = underlyingToken.balanceOf(user);
        uint balanceSharesBefore = wrapper.balanceOf(user);

        vm.startPrank(user);
        underlyingToken.forceApprove(address(wrapper), amountToDeposit);
        uint mintedShares = wrapper.deposit(amountToDeposit, user);
        vm.stopPrank();

        uint balanceUnderlyingAfter = underlyingToken.balanceOf(user);
        uint balanceSharesAfter = wrapper.balanceOf(user);

        assertEq(balanceUnderlyingAfter, balanceUnderlyingBefore - amountToDeposit, "Deposit is not EXACT_IN");
        assertEq(balanceSharesAfter, balanceSharesBefore + mintedShares, "Deposit minted shares do not match");
        assertApproxEqAbs(
            convertedShares, mintedShares, TOLERANCE, "Convert and actual operation difference is higher than tolerance"
        );
        assertApproxEqAbs(
            previewedShares, mintedShares, TOLERANCE, "Preview and actual operation difference is higher than tolerance"
        );

        // Mint _at least_ previewed shares.
        assertGe(mintedShares, previewedShares, "Minted shares is lower than converted minted");
    }

    function testMint__Fork__Fuzz(uint amountToMint) public {
        // When user mints, a round up may occur and add some wei in the amount of underlying required to deposit.
        // This can cause the user to not have enough tokens to deposit.
        // So, the maximum amountToMint must be the initialShares (which is exactly the initialUnderlying, converted to
        // shares) less a tolerance.
        amountToMint = bound(
            amountToMint,
            minDeposit * underlyingToWrappedFactor,
            userInitialShares - (TOLERANCE * underlyingToWrappedFactor)
        );

        uint convertedUnderlying = wrapper.convertToAssets(amountToMint);
        uint previewedUnderlying = wrapper.previewMint(amountToMint);

        uint balanceUnderlyingBefore = underlyingToken.balanceOf(user);
        uint balanceSharesBefore = wrapper.balanceOf(user);

        vm.startPrank(user);
        underlyingToken.forceApprove(address(wrapper), previewedUnderlying);
        uint depositedUnderlying = wrapper.mint(amountToMint, user);
        vm.stopPrank();

        uint balanceUnderlyingAfter = underlyingToken.balanceOf(user);
        uint balanceSharesAfter = wrapper.balanceOf(user);

        assertEq(balanceUnderlyingAfter, balanceUnderlyingBefore - depositedUnderlying, "Mint assets do not match");
        assertEq(balanceSharesAfter, balanceSharesBefore + amountToMint, "Mint is not EXACT_OUT");
        assertApproxEqAbs(
            convertedUnderlying,
            depositedUnderlying,
            TOLERANCE,
            "Convert and actual operation difference is higher than tolerance"
        );
        assertApproxEqAbs(
            previewedUnderlying,
            depositedUnderlying,
            TOLERANCE,
            "Preview and actual operation difference is higher than tolerance"
        );

        // Deposit _at most_ `previewedUnderlying`.
        assertGe(previewedUnderlying, depositedUnderlying, "Previewed underlying is lower than converted deposited");
    }

    function testWithdraw__Fork__Fuzz(uint amountToWithdraw) public {
        // When user deposited to underlying, a round down may occur and remove some wei. So, makes sure
        // amountToWithdraw does not pass the amount deposited - a wei tolerance.
        amountToWithdraw = bound(amountToWithdraw, minDeposit, userInitialUnderlying - TOLERANCE);

        uint convertedShares = wrapper.convertToShares(amountToWithdraw);
        uint previewedShares = wrapper.previewWithdraw(amountToWithdraw);

        uint balanceUnderlyingBefore = underlyingToken.balanceOf(user);
        uint balanceSharesBefore = wrapper.balanceOf(user);

        vm.prank(user);

        uint burnedShares = wrapper.withdraw(amountToWithdraw, user, user);

        uint balanceUnderlyingAfter = underlyingToken.balanceOf(user);
        uint balanceSharesAfter = wrapper.balanceOf(user);

        assertEq(balanceUnderlyingAfter, balanceUnderlyingBefore + amountToWithdraw, "Withdraw is not EXACT_OUT");
        assertEq(balanceSharesAfter, balanceSharesBefore - burnedShares, "Withdraw burned shares do not match");
        assertApproxEqAbs(
            convertedShares, burnedShares, TOLERANCE, "Convert and actual operation difference is higher than tolerance"
        );
        assertApproxEqAbs(
            previewedShares, burnedShares, TOLERANCE, "Preview and actual operation difference is higher than tolerance"
        );

        // Burn _at most_ previewed shares.
        assertGe(previewedShares, burnedShares, "Previewed shares is lower than converted burned");
    }

    function testRedeem__Fork__Fuzz(uint amountToRedeem) public {
        // When user deposited to underlying, a round down may occur and remove some wei. So, makes sure
        // amountToWithdraw does not pass the amount deposited - a wei tolerance.
        amountToRedeem = bound(amountToRedeem, minDeposit * underlyingToWrappedFactor, userInitialShares - TOLERANCE);

        uint convertedAssets = wrapper.convertToAssets(amountToRedeem);
        uint previewedAssets = wrapper.previewRedeem(amountToRedeem);

        uint balanceUnderlyingBefore = underlyingToken.balanceOf(user);
        uint balanceSharesBefore = wrapper.balanceOf(user);

        vm.startPrank(user);
        uint withdrawnAssets = wrapper.redeem(amountToRedeem, user, user);
        vm.stopPrank();

        uint balanceUnderlyingAfter = underlyingToken.balanceOf(user);
        uint balanceSharesAfter = wrapper.balanceOf(user);

        assertEq(balanceUnderlyingAfter, balanceUnderlyingBefore + withdrawnAssets, "Redeem is not EXACT_IN");
        assertEq(balanceSharesAfter, balanceSharesBefore - amountToRedeem, "Redeem burned shares do not match");
        assertApproxEqAbs(
            convertedAssets,
            withdrawnAssets,
            TOLERANCE,
            "Convert and actual operation difference is higher than tolerance"
        );
        assertApproxEqAbs(
            previewedAssets,
            withdrawnAssets,
            TOLERANCE,
            "Preview and actual operation difference is higher than tolerance"
        );

        // Withdraw _at least_ `previewedAssets`.
        assertGe(withdrawnAssets, previewedAssets, "Previewed assets is lower than converted withdrawn");
    }

    function _setupAllowance(address sender) private {
        vm.startPrank(sender);
        underlyingToken.forceApprove(address(wrapper), type(uint).max);
        vm.stopPrank();
    }

    function _initializeWallet(address receiver) private {
        uint initialDeposit = amountToDonate / 2;

        vm.prank(underlyingDonor);
        underlyingToken.safeTransfer(receiver, amountToDonate);

        vm.startPrank(receiver);
        underlyingToken.forceApprove(address(wrapper), initialDeposit);
        wrapper.deposit(initialDeposit, receiver);
        vm.stopPrank();
    }

    /**
     * @notice Defines network, overrideBlockNumber, wrapper, underlyingDonor and amountToDonate.
     * @dev Make sure the underlyingDonor has at least 3 times the amountToDonate amount in underlying tokens, and
     * that the buffer was not been initialized for the ERC4626 token in the current block number.
     */
    function setUpForkTestVariables() internal virtual;

    function _upgradeThings() internal virtual {}
}
