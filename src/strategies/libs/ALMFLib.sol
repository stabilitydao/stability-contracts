// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./LeverageLendingLib.sol";
import {ALMFCalcLib} from "./ALMFCalcLib.sol";
import {IAToken} from "../../integrations/aave/IAToken.sol";
import {IAlgebraFlashCallback} from "../integrations/algebrav4/callback/IAlgebraFlashCallback.sol";
import {IBalancerV3FlashCallback} from "../integrations/balancerv3/IBalancerV3FlashCallback.sol";
import {IControllable} from "../../interfaces/IControllable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFlashLoanRecipient} from "../integrations/balancer/IFlashLoanRecipient.sol";
import {ILeverageLendingStrategy} from "../../interfaces/ILeverageLendingStrategy.sol";
import {IPool} from "../../integrations/aave/IPool.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {IUniswapV3FlashCallback} from "../integrations/uniswapv3/IUniswapV3FlashCallback.sol";
import {IVaultMainV3} from "../integrations/balancerv3/IVaultMainV3.sol";
import {StrategyLib} from "./StrategyLib.sol";


library ALMFLib {
    uint public constant FARM_ADDRESS_LENDING_VAULT_INDEX = 0;
    uint public constant FARM_ADDRESS_BORROWING_VAULT_INDEX = 1;
    uint public constant FARM_ADDRESS_FLASH_LOAN_VAULT_INDEX = 2;

    uint public constant INTEREST_RATE_MODE_VARIABLE = 2;

//region ------------------------------------- Flash loan
    /// @notice token Borrow asset
    /// @notice amount Flash loan amount in borrow asset
    function _receiveFlashLoan(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address token,
        uint amount,
        uint feeAmount
    ) internal {
        address collateralAsset = $.collateralAsset;
        address flashLoanVault = $.flashLoanVault;
        require(msg.sender == flashLoanVault, IControllable.IncorrectMsgSender());

        // Reward asset can be equal to the borrow asset. Rewards can be transferred to the strategy at any moment.
        // If any borrow asset is on the balance before taking flash loan it can be only rewards.
        // All rewards are processed by hardwork and cannot be used before hardwork.
        // So, we need to keep reward amount on balance after exit this function.
        uint tokenBalance0 = IERC20(token).balanceOf(address(this));
        tokenBalance0 = tokenBalance0 > amount ? tokenBalance0 - amount : 0;

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.Deposit) {
            // swap
            _swap(platform, token, collateralAsset, amount, $.swapPriceImpactTolerance0);

            // supply todo can rewards be in collateral asset? then we need to exclude them from supply amount
            IPool(IAToken($.lendingVault).POOL()).supply(collateralAsset, IERC20(collateralAsset).balanceOf(address(this)), address(this), 0);

            // borrow
            IPool(IAToken($.borrowingVault).POOL()).borrow(token, amount + feeAmount, INTEREST_RATE_MODE_VARIABLE, address(this), 0);

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.Withdraw) {
            uint tempCollateralAmount = $.tempCollateralAmount;
            uint swapPriceImpactTolerance0 = $.swapPriceImpactTolerance0;

            // repay debt
            IPool(IAToken($.borrowingVault).POOL()).repay(token, amount, INTEREST_RATE_MODE_VARIABLE, address(this));

            // withdraw
            {
                address lendingVault = $.lendingVault;
                uint collateralAmountTotal = totalCollateral(lendingVault);
                collateralAmountTotal -= collateralAmountTotal / 1000; // todo do we need it?

                IPool(IAToken(lendingVault).POOL()).withdraw(
                    collateralAsset,
                    Math.min(tempCollateralAmount, collateralAmountTotal),
                    address(this)
                );
            }

            // swap
            _swap(
                platform,
                collateralAsset,
                token,
                ALMFCalcLib._estimateSwapAmount(
                    platform, amount + feeAmount, collateralAsset, token, swapPriceImpactTolerance0, tokenBalance0
                ),
                // Math.min(tempCollateralAmount, StrategyLib.balance(collateralAsset)),
                swapPriceImpactTolerance0
            );

            // explicit error for the case when _estimateSwapAmount gives incorrect amount
            require(
                ALMFCalcLib._balanceWithoutRewards(token, tokenBalance0) >= amount + feeAmount, IControllable.InsufficientBalance()
            );

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // swap unnecessary borrow asset back to collateral
            _swap(
                platform,
                token,
                collateralAsset,
                ALMFCalcLib._balanceWithoutRewards(token, tokenBalance0),
                swapPriceImpactTolerance0
            );

            // reset temp vars
            $.tempCollateralAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.DecreaseLtv) {
            address lendingVault = $.lendingVault;

            // repay
            IPool(IAToken($.borrowingVault).POOL()).repay(token, ALMFCalcLib._balanceWithoutRewards(token, tokenBalance0), INTEREST_RATE_MODE_VARIABLE, address(this));

            // withdraw amount
            IPool(IAToken((lendingVault).POOL())).withdraw(collateralAsset, $.tempCollateralAmount, address(this));

            // swap
            _swap(platform, collateralAsset, token, $.tempCollateralAmount, $.swapPriceImpactTolerance1);

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // repay remaining balance
            IPool(IAToken($.borrowingVault).POOL()).repay(token, ALMFCalcLib._balanceWithoutRewards(token, tokenBalance0), INTEREST_RATE_MODE_VARIABLE, address(this));

            $.tempCollateralAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.IncreaseLtv) {
            uint tempCollateralAmount = $.tempCollateralAmount;

            // swap
            _swap(
                platform,
                token,
                collateralAsset,
                ALMFCalcLib._balanceWithoutRewards(token, tokenBalance0) * $.increaseLtvParam1 / ALMFCalcLib.INTERNAL_PRECISION,
                $.swapPriceImpactTolerance1
            );

            // supply
            IPool(IAToken($.lendingVault).POOL()).deposit(
                collateralAsset,
                ALMFCalcLib._getLimitedAmount(IERC20(collateralAsset).balanceOf(address(this)), tempCollateralAmount),
                address(this),
                0
            );

            // borrow
            IPool(IAToken($.borrowingVault).POOL()).borrow(token, amount + feeAmount, INTEREST_RATE_MODE_VARIABLE, 0, address(this));

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // repay not used borrow
            uint tokenBalance = ALMFCalcLib._balanceWithoutRewards(token, tokenBalance0);
            if (tokenBalance != 0) {
                IPool(IAToken($.borrowingVault).POOL()).repay(token, tokenBalance, INTEREST_RATE_MODE_VARIABLE, address(this));
            }

            // reset temp vars
            if (tempCollateralAmount != 0) {
                $.tempCollateralAmount = 0;
            }
        }

        // ensure that all rewards are still exist on the balance
        require(tokenBalance0 == IERC20(token).balanceOf(address(this)), IControllable.IncorrectBalance());

        (uint ltv,, uint leverage,,,) = health(platform, $);
        emit ILeverageLendingStrategy.LeverageLendingHealth(ltv, leverage);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.None;
    }

    function receiveFlashLoanBalancerV2(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address[] memory tokens,
        uint[] memory amounts,
        uint[] memory feeAmounts
    ) external {
        // Flash loan is performed upon deposit and withdrawal
        ALMFLib._receiveFlashLoan(platform, $, tokens[0], amounts[0], feeAmounts[0]);
    }

    function receiveFlashLoanV3(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address token,
        uint amount
    ) external {
        // sender is vault, it's checked inside receiveFlashLoan
        // we can use msg.sender below but $.flashLoanVault looks more safe
        IVaultMainV3 vault = IVaultMainV3(payable($.flashLoanVault));

        // ensure that the vault has available amount
        require(IERC20(token).balanceOf(address(vault)) >= amount, IControllable.InsufficientBalance());

        // receive flash loan from the vault
        vault.sendTo(token, address(this), amount);

        // Flash loan is performed upon deposit and withdrawal
        ALMFLib._receiveFlashLoan(platform, $, token, amount, 0); // assume that flash loan is free, fee is 0

        // return flash loan back to the vault
        // assume that the amount was transferred back to the vault inside receiveFlashLoan()
        // we need only to register this transferring
        vault.settle(token, amount);
    }

    function uniswapV3FlashCallback(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        uint fee0,
        uint fee1,
        bytes calldata userData
    ) external {
        // sender is the pool, it's checked inside receiveFlashLoan
        (address token, uint amount, bool isToken0) = abi.decode(userData, (address, uint, bool));
        ALMFLib._receiveFlashLoan(platform, $, token, amount, isToken0 ? fee0 : fee1);
    }

//endregion ------------------------------------- Flash loan

//region ------------------------------------- Deposit
    function depositAssets(
        address platform_,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IStrategy.StrategyBaseStorage storage $base,
        uint amount,
        address asset
    ) external returns (uint value) {
        ILeverageLendingStrategy.LeverageLendingAddresses memory v = _getLeverageLendingAddresses($);

        ALMFCalcLib.State memory state; // todo get state

        uint valueWas = StrategyLib.balance(asset) + calcTotal(v, state);

        _deposit(platform_, $, v, amount, state);

        state; // todo refresh state
        uint valueNow = StrategyLib.balance(asset) + calcTotal(v, state);

        if (valueNow > valueWas) {
            value = amount + (valueNow - valueWas);
        } else {
            value = amount - (valueWas - valueNow);
        }

        $base.total += value;

        // ensure that result LTV doesn't exceed max
        (uint maxLtv,,) = getLtvData(v.lendingVault, $.targetLeveragePercent);
        _ensureLtvValid($, maxLtv);
    }

    /// @notice Deposit with leverage: if current leverage is above target, first repay debt directly, then deposit with flash loan;
    function _deposit(
        address platform_,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        uint amountToDeposit,
        ALMFCalcLib.State memory state
    ) internal {
        uint leverage = ALMFCalcLib.getLeverage(state.collateralBase, state.debtBase);
        if (leverage > state.targetLeverage) {
            (uint ar, uint ad) = ALMFCalcLib.splitDepositAmount(
                amountToDeposit,
                state.targetLeverage,
                state.collateralBase,
                state.debtBase,
                state.swapFee
            );
            if (ar != 0) { // todo  > threshold
                // restore leverage using direct repay
                _directRepay(platform_, $, v, ar);
            }
            if (ad != 0) {
                if (ar != 0) {
                    state; // todo refresh state
                }
                // deposit remain amount with leverage
                _depositWithFlash($, v, ad);
            }
        } else {
            _depositWithFlash($, v, amountToDeposit);
        }
    }

    function _directRepay(
        address platform_,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        uint amountToDeposit
    ) internal {
        // we need to remember balance to exclude possible rewards from the amount to repay
        uint borrowBalanceBefore = StrategyLib.balance(v.borrowAsset);

        // swap amount to borrow asset
        _swap(platform_, v.collateralAsset, v.borrowAsset, amountToDeposit, $.swapPriceImpactTolerance0);

        // use all balance of borrow asset to repay debt
        address pool = IAToken(v.borrowingVault).POOL();
        uint amount = StrategyLib.balance(v.borrowAsset) - borrowBalanceBefore;
        if (amount != 0) {
            IERC20(v.borrowAsset).approve(pool, amount);
            IPool(pool).repay(v.borrowAsset, amount, INTEREST_RATE_MODE_VARIABLE, address(this));
        }
    }

    function _depositWithFlash(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        uint amountToDeposit,
        ALMFCalcLib.State memory state
    ) internal {
        uint borrowAmount = _getDepositFlashAmount($, v, amountToDeposit);
        (address[] memory flashAssets, uint[] memory flashAmounts) = _getFlashLoanAmounts(borrowAmount, v.borrowAsset);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.Deposit;
        LeverageLendingLib.requestFlashLoan($, flashAssets, flashAmounts);
    }

    function _getDepositFlashAmount(uint amountToDeposit, ALMFCalcLib.State memory state) internal view returns (uint flashAmount) {
        uint amountBase = ALMFCalcLib.collateralToBase(amountToDeposit, state.data.priceC, state.data.decimalsC);
        uint den = state.targetLeverage * (state.swapFee + state.flashFee) / ALMFCalcLib.INTERNAL_PRECISION + (ALMFCalcLib.INTERNAL_PRECISION - state.swapFee);
        uint num = state.targetLeverage * (state.collateralBase + amountBase + state.debtBase) - (state.collateralBase + amountBase) * ALMFCalcLib.INTERNAL_PRECISION;

        flashAmount = ALMFCalcLib.baseToBorrow(num * 1e18 / den, state.data.priceB, state.data.decimalsB);
    }
//endregion ------------------------------------- Deposit

//region ------------------------------------- Withdraw
    function withdrawAssets(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IStrategy.StrategyBaseStorage storage $base,
        uint value,
        address receiver
    ) external returns (uint[] memory amountsOut) {
        ILeverageLendingStrategy.LeverageLendingAddresses memory v = _getLeverageLendingAddresses($);
        ALMFCalcLib.State memory state; // todo get state
        uint collateralBalanceStrategy = StrategyLib.balance(v.collateralAsset);
        uint valueWas = collateralBalanceStrategy + calcTotal(v, state);

        // ---------------------- withdraw from the lending vault - only if amount on the balance is not enough
        if (value > collateralBalanceStrategy) {
            // it's too dangerous to ask value - state.collateralBalanceStrategy
            // because current balance is used in multiple places inside receiveFlashLoan
            // so we ask to withdraw full required amount
            withdrawFromLendingVault(platform, $, v, state, value);
            state; // todo refresh state
        }

        // ---------------------- Transfer required amount to the user, update base.total
        uint bal = StrategyLib.balance(v.collateralAsset);
        uint valueNow = bal + calcTotal(v, state);

        amountsOut = new uint[](1);
        if (valueWas > valueNow) {
            amountsOut[0] = Math.min(value - (valueWas - valueNow), bal);
        } else {
            amountsOut[0] = Math.min(value + (valueNow - valueWas), bal);
        }

        if (receiver != address(this)) {
            IERC20(v.collateralAsset).safeTransfer(receiver, amountsOut[0]);
        }

        $base.total -= value;

        // ensure that result LTV doesn't exceed max
        _ensureLtvValid($, state.maxLtv);
    }

    function withdrawFromLendingVault(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        ALMFCalcLib.State memory state,
        uint value
    ) internal {
        CollateralDebtState memory debtState =
                        _getDebtState(platform, v.lendingVault, v.collateralAsset, v.borrowAsset, v.borrowingVault);
        (,, uint leverage,,,) = _health(platform, $, debtState);

        if (0 == debtState.debtAmount) {
            // zero debt, positive collateral - we can just withdraw required amount
            uint amountToWithdraw = Math.min(
                value > debtState.collateralBalance ? value - debtState.collateralBalance : 0,
                debtState.collateralAmount
            );
            if (amountToWithdraw != 0) {
                IPool(IAToken(v.lendingVault).POOL()).withdraw(v.collateralAsset, amountToWithdraw, address(this));
            }
        } else {
            _defaultWithdraw($, v, state, value);
        }
    }

    /// @notice Default withdraw procedure (leverage is a bit decreased)
    function _defaultWithdraw(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        ALMFCalcLib.State memory state,
        uint value
    ) internal {
        // repay debt and withdraw
        // we use maxLeverage and maxLtv, so result ltv will reduce
        uint collateralAmountToWithdraw = value * state.maxLeverage * state.withdrawParam0 / ALMFCalcLib.INTERNAL_PRECISION / ALMFCalcLib.INTERNAL_PRECISION;

        uint[] memory flashAmounts = new uint[](1);
        flashAmounts[0] = collateralAmountToWithdraw * state.maxLtv / 1e18 * state.priceCtoB
            * (10 ** IERC20Metadata(v.borrowAsset).decimals()) / 1e18 // priceCtoB has decimals 1e18
            / (10 ** IERC20Metadata(v.collateralAsset).decimals());
        address[] memory flashAssets = new address[](1);
        flashAssets[0] = $.borrowAsset;

        $.tempCollateralAmount = collateralAmountToWithdraw;
        $.tempAction = ILeverageLendingStrategy.CurrentAction.Withdraw;
        LeverageLendingLib.requestFlashLoan($, flashAssets, flashAmounts);
    }

//endregion ------------------------------------- Withdraw

//region ------------------------------------- View
    function calcTotal(
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        ALMFCalcLib.State memory state
    ) internal pure returns (uint totalValue) {
        return ALMFCalcLib.baseToCollateral(state.collateralBase - state.debtBase, state.data.priceC, state.data.decimalsC);
    }

//endregion ------------------------------------- View

//region ------------------------------------- Swap
    function _swap(
        address platform,
        address tokenIn,
        address tokenOut,
        uint amount,
        uint priceImpactTolerance
    ) internal {
        ISwapper swapper = ISwapper(IPlatform(platform).swapper());
        swapper.swap(tokenIn, tokenOut, amount, priceImpactTolerance);
    }
//endregion ------------------------------------- Swap

//region ------------------------------------- Internal utils
    function _getFlashLoanAmounts(
        uint borrowAmount,
        address borrowAsset
    ) internal pure returns (address[] memory flashAssets, uint[] memory flashAmounts) {
        flashAssets = new address[](1);
        flashAssets[0] = borrowAsset;
        flashAmounts = new uint[](1);
        flashAmounts[0] = borrowAmount;
    }

    function _getLeverageLendingAddresses(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $
    ) internal view returns (ILeverageLendingStrategy.LeverageLendingAddresses memory) {
        return ILeverageLendingStrategy.LeverageLendingAddresses({
            collateralAsset: $.collateralAsset,
            borrowAsset: $.borrowAsset,
            lendingVault: $.lendingVault,
            borrowingVault: $.borrowingVault
        });
    }
//endregion ------------------------------------- Internal utils
}