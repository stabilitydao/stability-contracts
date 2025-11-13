// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol"; // todo
import {IFactory} from "../../interfaces/IFactory.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ALMFCalcLib} from "./ALMFCalcLib.sol";
import {IAToken} from "../../integrations/aave/IAToken.sol";
import {IAaveAddressProvider} from "../../integrations/aave/IAaveAddressProvider.sol";
import {IAavePriceOracle} from "../../integrations/aave/IAavePriceOracle.sol";
import {IControllable} from "../../interfaces/IControllable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILeverageLendingStrategy} from "../../interfaces/ILeverageLendingStrategy.sol";
import {IPool} from "../../integrations/aave/IPool.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {IVaultMainV3} from "../../integrations/balancerv3/IVaultMainV3.sol";
import {LeverageLendingLib} from "./LeverageLendingLib.sol";
import {StrategyLib} from "./StrategyLib.sol";
import {IAaveDataProvider} from "../../integrations/aave/IAaveDataProvider.sol";
import {ConstantsLib} from "../../core/libs/ConstantsLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


library ALMFLib {
    using SafeERC20 for IERC20;

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
        console.log("_receiveFlashLoan", amount, feeAmount);
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
            console.log("swap.borrow", amount);
            // swap
            _swap(platform, token, collateralAsset, amount, $.swapPriceImpactTolerance0);

            console.log("supply.collateral", IERC20(collateralAsset).balanceOf(address(this)));
            // supply: assume here that rewards in collateral are not possible
            IPool(IAToken($.lendingVault).POOL()).supply(collateralAsset, IERC20(collateralAsset).balanceOf(address(this)), address(this), 0);

            console.log("borrow", amount + feeAmount);
            // borrow
            IPool(IAToken($.borrowingVault).POOL()).borrow(token, amount + feeAmount, INTEREST_RATE_MODE_VARIABLE, 0, address(this));

            console.log("pay flash loan");
            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.Withdraw) {
            uint tempCollateralAmount = $.tempCollateralAmount;
            uint swapPriceImpactTolerance0 = $.swapPriceImpactTolerance0;
            console.log("withdraw using flash.tempCollateralAmount", tempCollateralAmount);

            console.log("repay.amount", amount);
            // repay debt
            IPool(IAToken($.borrowingVault).POOL()).repay(token, amount, INTEREST_RATE_MODE_VARIABLE, address(this));

            // withdraw
            {
                address lendingVault = $.lendingVault;
                uint collateralAmountTotal = totalCollateral(lendingVault);
                console.log("withdraw.collateralAmountTotal", collateralAmountTotal);
                // todo emergency? collateralAmountTotal -= collateralAmountTotal / 1000; // todo do we need it?

                console.log("withdraw.collateralAmountTotal.final", collateralAmountTotal);
                IPool(IAToken(lendingVault).POOL()).withdraw(
                    collateralAsset,
                    Math.min(tempCollateralAmount, collateralAmountTotal),
                    address(this)
                );
            }

            console.log("withdraw.swap", ALMFCalcLib.estimateSwapAmount(platform, amount + feeAmount, collateralAsset, token, swapPriceImpactTolerance0, tokenBalance0));
            // swap
            _swap(
                platform,
                collateralAsset,
                token,
                ALMFCalcLib.estimateSwapAmount(
                    platform, amount + feeAmount, collateralAsset, token, swapPriceImpactTolerance0, tokenBalance0
                ),
                // Math.min(tempCollateralAmount, StrategyLib.balance(collateralAsset)),
                swapPriceImpactTolerance0
            );

            // explicit error for the case when _estimateSwapAmount gives incorrect amount
            require(
                ALMFCalcLib.balanceWithoutRewards(token, tokenBalance0) >= amount + feeAmount, IControllable.InsufficientBalance()
            );

            console.log("pay flash loan", amount, feeAmount);
            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            console.log("swap back", ALMFCalcLib.balanceWithoutRewards(token, tokenBalance0));
            // swap unnecessary borrow asset back to collateral
            _swap(
                platform,
                token,
                collateralAsset,
                ALMFCalcLib.balanceWithoutRewards(token, tokenBalance0),
                swapPriceImpactTolerance0
            );

            // reset temp vars
            $.tempCollateralAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.DecreaseLtv) {
            console.log("decreaseLtv");
            address lendingVault = $.lendingVault;

            console.log("repay");
            // repay
            IPool(IAToken($.borrowingVault).POOL()).repay(token, ALMFCalcLib.balanceWithoutRewards(token, tokenBalance0), INTEREST_RATE_MODE_VARIABLE, address(this));

            console.log("withdraw");
            // withdraw amount
            IPool(IAToken(lendingVault).POOL()).withdraw(collateralAsset, $.tempCollateralAmount, address(this));

            console.log("swap");
            // swap
            _swap(platform, collateralAsset, token, $.tempCollateralAmount, $.swapPriceImpactTolerance1);

            console.log("pay flash loan");
            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // repay remaining balance
            IPool(IAToken($.borrowingVault).POOL()).repay(token, ALMFCalcLib.balanceWithoutRewards(token, tokenBalance0), INTEREST_RATE_MODE_VARIABLE, address(this));

            $.tempCollateralAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.IncreaseLtv) {
            console.log("IncreaseLtv");
            uint tempCollateralAmount = $.tempCollateralAmount;

            console.log("swap", ALMFCalcLib.balanceWithoutRewards(token, tokenBalance0) * $.increaseLtvParam1 / ALMFCalcLib.INTERNAL_PRECISION);
            // swap
            _swap(
                platform,
                token,
                collateralAsset,
                ALMFCalcLib.balanceWithoutRewards(token, tokenBalance0) * $.increaseLtvParam1 / ALMFCalcLib.INTERNAL_PRECISION,
                $.swapPriceImpactTolerance1
            );

            console.log("supply", ALMFCalcLib.getLimitedAmount(IERC20(collateralAsset).balanceOf(address(this)), tempCollateralAmount));
            // supply
            IPool(IAToken($.lendingVault).POOL()).deposit(
                collateralAsset,
                ALMFCalcLib.getLimitedAmount(IERC20(collateralAsset).balanceOf(address(this)), tempCollateralAmount),
                address(this),
                0
            );

            console.log("borrow", amount + feeAmount);
            // borrow
            IPool(IAToken($.borrowingVault).POOL()).borrow(token, amount + feeAmount, INTEREST_RATE_MODE_VARIABLE, 0, address(this));

            console.log("pay flash loan");
            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // repay not used borrow
            uint tokenBalance = ALMFCalcLib.balanceWithoutRewards(token, tokenBalance0);
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

        (, , , , uint ltv, ) = IPool(IAToken($.lendingVault).POOL()).getUserAccountData(address(this));
        emit ILeverageLendingStrategy.LeverageLendingHealth(ltv, ALMFCalcLib.ltvToLeverage(ltv));

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
    /// @notice Deposit {amount} of the collateral asset
    /// @param amount Amount of collateral asset to deposit
    /// @return value Value is calculated as a delta of (total collateral - total debt) in base assets (USDC, 18 decimals)
    function depositAssets(
        address platform_,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IFactory.Farm memory farm,
        uint amount
    ) external returns (uint value) {
        console.log("============================= depositAssets.amount", amount);
        ALMFCalcLib.StaticData memory data = _getStaticData(platform_, $, farm);
        ALMFCalcLib.State memory state = _getState(data);

        uint valueWas = ALMFCalcLib.collateralToBase(StrategyLib.balance(data.collateralAsset), data) + calcTotal(state);
        console.log("depositAssets.valueWas", valueWas);

        if (amount > 1e12) { // todo threshold for small deposits
            _deposit(platform_, $, data, amount, state);
        } else {
            // todo supply without leverage, don't leave amount on balance
        }

        state = _getState(data); // refresh state after deposit
        uint valueNow = ALMFCalcLib.collateralToBase(StrategyLib.balance(data.collateralAsset), data) + calcTotal(state);
        console.log("depositAssets.valueNow", valueNow);

        if (valueNow > valueWas) {
            value = ALMFCalcLib.collateralToBase(amount, data) + (valueNow - valueWas);
        } else {
            console.log("ALMFCalcLib.collateralToBase(amount, data)", ALMFCalcLib.collateralToBase(amount, data));
            console.log("valueWas - valueNow", valueWas - valueNow);
            // todo deposit 1 decimal, amount base is 3431, valueWas - valueNow 5912220594977
            value = ALMFCalcLib.collateralToBase(amount, data) - (valueWas - valueNow);
        }
        console.log("depositAssets.value", value);

        _ensureLtvValid(state);
        console.log("============================== depositAssets.done");
    }

    /// @notice Deposit with leverage: if current leverage is above target, first repay debt directly, then deposit with flash loan;
    function _deposit(
        address platform_,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ALMFCalcLib.StaticData memory data,
        uint amountToDeposit,
        ALMFCalcLib.State memory state
    ) internal {
        uint leverage = ALMFCalcLib.getLeverage(state.collateralBase, state.debtBase);
        console.log("leverage, maxTargetLeverage", leverage, data.maxTargetLeverage);
        if (leverage > data.maxTargetLeverage) {
            (uint ar, uint ad) = ALMFCalcLib.splitDepositAmount(
                amountToDeposit,
                (data.minTargetLeverage + data.maxTargetLeverage) / 2,
                state.collateralBase,
                state.debtBase,
                data.swapFee18
            );
            console.log("ar, ad", ar, ad);
            bool repayRequired = ar != 0; // todo  > threshold;
            if (repayRequired) { // todo  > threshold
                console.log("direct repay", ar);
                // restore leverage using direct repay
                _directRepay(platform_, data, ar);
            }
            if (ad != 0) {
                if (repayRequired) {
                    state = _getState(data); // refresh state after direct repay
                }
                console.log("deposit ad", ad);
                // deposit remain amount with leverage
                _depositWithFlash($, data, ad, state);
            }
        } else {
            console.log("normal deposit");
            _depositWithFlash($, data, amountToDeposit, state);
        }
    }

    /// @notice Directly repay debt by swapping a given part of collateral to borrow asset
    function _directRepay(
        address platform_,
        ALMFCalcLib.StaticData memory data,
        uint amountToDeposit
    ) internal {
        // we need to remember balance to exclude possible rewards (provided in borrow asset) from the amount to repay
        uint borrowBalanceBefore = StrategyLib.balance(data.borrowAsset);

        // swap amount to borrow asset
        _swap(platform_, data.collateralAsset, data.borrowAsset, amountToDeposit, data.swapFee18 * ConstantsLib.DENOMINATOR / 1e18);

        // use all balance of borrow asset to repay debt
        address pool = IAToken(data.borrowingVault).POOL();
        uint amountToRepay = StrategyLib.balance(data.borrowAsset) - borrowBalanceBefore;
        if (amountToRepay != 0) {
            IERC20(data.borrowAsset).approve(pool, amountToRepay);
            IPool(pool).repay(data.borrowAsset, amountToRepay, INTEREST_RATE_MODE_VARIABLE, address(this));
        }
    }

    /// @notice Deposit with flash loan
    function _depositWithFlash(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ALMFCalcLib.StaticData memory data,
        uint amountToDeposit,
        ALMFCalcLib.State memory state
    ) internal {
        uint borrowAmount = _getDepositFlashAmount(amountToDeposit, data, state);
        (address[] memory flashAssets, uint[] memory flashAmounts) = _getFlashLoanAmounts(borrowAmount, data.borrowAsset);
        console.log("flash borrowAmount", borrowAmount);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.Deposit;
        LeverageLendingLib.requestFlashLoan($, flashAssets, flashAmounts);
    }

    /// @notice Calculate amount to borrow in flash loan for deposit
    /// @param amountToDeposit Amount of collateral asset to deposit
    function _getDepositFlashAmount(uint amountToDeposit, ALMFCalcLib.StaticData memory data, ALMFCalcLib.State memory state) internal pure returns (uint flashAmount) {
        console.log("_getDepositFlashAmount.amountToDeposit", amountToDeposit);
        uint targetLeverage = (data.minTargetLeverage + data.maxTargetLeverage) / 2;
        uint amountBase = ALMFCalcLib._collateralToBase(amountToDeposit, data.priceC18, data.decimalsC);
        uint den = (targetLeverage * (data.swapFee18 + data.flashFee18) + (1e18 - data.swapFee18) * ALMFCalcLib.INTERNAL_PRECISION) / 1e18;
        uint num = targetLeverage * (state.collateralBase + amountBase - state.debtBase) - (state.collateralBase + amountBase) * ALMFCalcLib.INTERNAL_PRECISION;

        flashAmount = ALMFCalcLib._baseToBorrow(num / den, data.priceB18, data.decimalsB);

        console.log("_getDepositFlashAmount.targetLeverage", targetLeverage);
        console.log("_getDepositFlashAmount.amountBase", amountBase);
        console.log("_getDepositFlashAmount.den", den);
        console.log("_getDepositFlashAmount.num", num);
        console.log("_getDepositFlashAmount.flashAmount", flashAmount);
        console.log("targetLeverage * (state.collateralBase + amountBase + state.debtBase)", targetLeverage * (state.collateralBase + amountBase - state.debtBase));
        console.log("targetLeverage", targetLeverage);
        console.log("state.collateralBase", state.collateralBase);
        console.log("amountBase", amountBase);
        console.log("state.debtBase", state.debtBase);
        console.log("(state.collateralBase + amountBase) * ALMFCalcLib.INTERNAL_PRECISION", (state.collateralBase + amountBase) * ALMFCalcLib.INTERNAL_PRECISION);
    }
//endregion ------------------------------------- Deposit

//region ------------------------------------- Withdraw
    /// @notice Withdraw {value} from the strategy to {receiver}
    /// @param value Value to withdraw in base asset (USD, 18 decimals)
    function withdrawAssets(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IFactory.Farm memory farm,
        uint value,
        address receiver
    ) external returns (uint[] memory amountsOut) {
        console.log("--------------------------------------- withdrawAssets.value", value);
        ALMFCalcLib.StaticData memory data = _getStaticData(platform, $, farm);
        ALMFCalcLib.State memory state = _getState(data);

        uint collateralBalanceBase = ALMFCalcLib.collateralToBase(StrategyLib.balance(data.collateralAsset), data);
        uint valueWas = collateralBalanceBase + calcTotal(state);
        console.log("withdrawAssets.collateralBalanceBase", collateralBalanceBase);
        console.log("withdrawAssets.valueWas", valueWas);

        // ---------------------- withdraw from the lending vault - only if amount on the balance is not enough
        if (value > collateralBalanceBase) {
            // it's too dangerous to ask to withdraw (value - state.collateralBalanceStrategy)
            // because current balance is used in multiple places inside receiveFlashLoan
            // so we ask to withdraw full required amount
            _withdrawRequiredAmountOnBalance($, data, state, value);
            state = _getState(data);
        }

        // ---------------------- Transfer required amount to the user
        uint balBase = ALMFCalcLib.collateralToBase(StrategyLib.balance(data.collateralAsset), data);
        uint valueNow = balBase + calcTotal(state);
        console.log("withdrawAssets.balBase", balBase);
        console.log("withdrawAssets.valueNow", valueNow);

        amountsOut = new uint[](1);
        if (valueWas > valueNow) {
            amountsOut[0] = ALMFCalcLib.baseToCollateral(Math.min(value - (valueWas - valueNow), balBase), data);
        } else {
            amountsOut[0] = ALMFCalcLib.baseToCollateral(Math.min(value + (valueNow - valueWas), balBase), data);
        }
        console.log("withdrawAssets.amountsOut[0]", amountsOut[0]);

        // todo check amountsOut >= actual balance

        if (receiver != address(this)) {
            console.log("withdrawAssets.transfer to receiver", receiver);
            IERC20(data.collateralAsset).safeTransfer(receiver, amountsOut[0]);
        }

        _ensureLtvValid(state);
        console.log("---------------------------------------- withdrawAssets.done");
        _getState(data); // todo remove
    }

    /// @notice Get required amount to withdraw on balance
    /// @param value Value to withdraw in base asset (USD, 18 decimals)
    function _withdrawRequiredAmountOnBalance(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ALMFCalcLib.StaticData memory data,
        ALMFCalcLib.State memory state,
        uint value
    ) internal {
        console.log("_withdrawRequiredAmountOnBalance");
        if (0 == state.debtBase) {
            console.log("_withdrawRequiredAmountOnBalance.1");
            // zero debt, positive supply - we can just withdraw missed amount from the lending pool

            // collateral amount on balance
            uint collateralBalanceBase = ALMFCalcLib.collateralToBase(StrategyLib.balance(data.collateralAsset), data);

            // collateral amount required to withdraw from lending pool
            uint amountToWithdraw = Math.min(
                value > collateralBalanceBase ? value - collateralBalanceBase : 0,
                state.collateralBase
            );

            if (amountToWithdraw != 0) {
                IPool(IAToken(data.lendingVault).POOL()).withdraw(data.collateralAsset, amountToWithdraw, address(this));
            }
        } else {
            console.log("_withdrawRequiredAmountOnBalance.2");
            _withdrawUsingFlash($, data, state, value);
        }
    }

    /// @notice Default withdraw procedure (leverage is a bit decreased)
    function _withdrawUsingFlash(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ALMFCalcLib.StaticData memory data,
        ALMFCalcLib.State memory state,
        uint value
    ) internal {
        console.log("_withdrawUsingFlash");
        uint leverage = ALMFCalcLib.getLeverage(state.collateralBase, state.debtBase);
        console.log("_withdrawUsingFlash.leverage", leverage);

        {
            // use leverage correction (coefficient k = withdrawParam0) if necessary: L_adj = L + k (TL - L)
            uint targetLeverage = (data.minTargetLeverage + data.maxTargetLeverage) / 2;
            if (leverage < data.minTargetLeverage) {
                leverage = leverage + $.withdrawParam0 * (targetLeverage - leverage);
            } else if (leverage > data.maxTargetLeverage) {
                leverage = leverage - $.withdrawParam0 * (leverage - targetLeverage);
            }
        }
        console.log("_withdrawUsingFlash.leverage.adj", leverage);

        (uint flashAmount, uint collateralToWithdraw) = ALMFCalcLib.calcWithdrawAmounts(value, leverage, data, state);
        console.log("_withdrawUsingFlash.flashAmount", flashAmount);
        console.log("_withdrawUsingFlash.collateralToWithdraw", collateralToWithdraw);

        if (flashAmount == 0) {
            console.log("direct withdraw");
            // special case: don't use flash, just withdraw required amount from aave and send it to the user
            IPool(IAToken(data.lendingVault).POOL()).withdraw(data.collateralAsset, collateralToWithdraw, address(this));
        } else {
            uint[] memory flashAmounts = new uint[](1);
            flashAmounts[0] = flashAmount;
            address[] memory flashAssets = new address[](1);
            flashAssets[0] = $.borrowAsset;

            $.tempCollateralAmount = collateralToWithdraw;

            $.tempAction = ILeverageLendingStrategy.CurrentAction.Withdraw;
            LeverageLendingLib.requestFlashLoan($, flashAssets, flashAmounts);
        }
        console.log("_withdrawUsingFlash.done");
    }

//endregion ------------------------------------- Withdraw

//region ------------------------------------- View
    /// @notice Calculate total value: collateral - debt in base asset (USD, 18 decimals)
    /// Balance on the strategy is NOT included.
    function calcTotal(ALMFCalcLib.State memory state) internal pure returns (uint totalValue) {
        totalValue = state.collateralBase - state.debtBase;
        console.log("calcTotal", totalValue);
    }

    /// @notice Get prices of collateral and borrow assets from Aave price oracle in USD, decimals 18
    function getPrices(address aaveAddressProvider, address collateralAsset, address borrowAsset)
        internal
        view
        returns (uint priceC, uint priceB)
    {
        address[] memory assets = new address[](2);
        assets[0] = collateralAsset;
        assets[1] = borrowAsset;

        uint[] memory prices = IAavePriceOracle(IAaveAddressProvider(aaveAddressProvider).getPriceOracle()).getAssetsPrices(assets);
        return (prices[0] * 1e10, prices[1] * 1e10); // Aave prices have 8 decimals, we need 18
    }

    /// @notice Get static data for deposit/withdraw calculations
    function _getStaticData(
        address platform_,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IFactory.Farm memory farm
    ) internal view returns (ALMFCalcLib.StaticData memory data) {
        data.platform = platform_;

        data.collateralAsset = $.collateralAsset;
        data.borrowAsset = $.borrowAsset;
        data.lendingVault = $.lendingVault;
        data.borrowingVault = $.borrowingVault;

        data.addressProvider = IPool(IAToken(data.lendingVault).POOL()).ADDRESSES_PROVIDER();

        data.flashLoanVault = $.flashLoanVault;
        data.flashLoanKind = $.flashLoanKind;

        data.swapFee18 = $.swapPriceImpactTolerance0 * 1e18 / ConstantsLib.DENOMINATOR;
        data.flashFee18 = LeverageLendingLib.getFlashFee18(data.flashLoanVault, data.flashLoanKind);

        data.decimalsC = IERC20Metadata(data.collateralAsset).decimals();
        data.decimalsB = IERC20Metadata(data.borrowAsset).decimals();
        (data.priceC18, data.priceB18) = ALMFLib.getPrices(data.addressProvider, data.collateralAsset, data.borrowAsset);

        (data.minTargetLeverage, data.maxTargetLeverage) = _getFarmLeverageConfig(farm);

        console.log("collateralAsset", data.collateralAsset);
        console.log("borrowAsset", data.borrowAsset);
        console.log("lendingVault", data.lendingVault);
        console.log("borrowingVault", data.borrowingVault);
//        console.log("flashLoanVault", data.flashLoanVault);
//        console.log("flashLoanKind", data.flashLoanKind);
        console.log("swapFee18", data.swapFee18);
        console.log("flashFee18", data.flashFee18);
        console.log("priceC18", data.priceC18);
        console.log("priceB18", data.priceB18);
        console.log("minTargetLeverage", data.minTargetLeverage);
        console.log("maxTargetLeverage", data.maxTargetLeverage);

        return data;
    }

    /// @return targetMinLeverage Minimum target leverage, INTERNAL_PRECISION
    /// @return targetMaxLeverage Maximum target leverage, INTERNAL_PRECISION
    function _getFarmLeverageConfig(IFactory.Farm memory farm) internal pure returns (uint targetMinLeverage, uint targetMaxLeverage) {
        return (
            ALMFCalcLib.ltvToLeverage(farm.nums[0]),
            ALMFCalcLib.ltvToLeverage(farm.nums[1])
        );
    }

    /// @return targetMinLtv Minimum target ltv, INTERNAL_PRECISION
    /// @return targetMaxLtv Maximum target ltv, INTERNAL_PRECISION
    function _getFarmLtvConfig(IFactory.Farm memory farm) internal pure returns (uint targetMinLtv, uint targetMaxLtv) {
        return (farm.nums[0], farm.nums[1]);
    }

    /// @notice Get current state: collateral and debt in base asset (USD, 18 decimals)
    function _getState(ALMFCalcLib.StaticData memory data) internal view returns (ALMFCalcLib.State memory state) {
        IPool pool = IPool(IAaveAddressProvider(data.addressProvider).getPool());

        (uint totalCollateralBase, uint totalDebtBase, , , uint maxLtv, uint healthFactor) = pool.getUserAccountData(address(this));

        state = ALMFCalcLib.State({
            collateralBase: totalCollateralBase * 1e10,
            debtBase: totalDebtBase * 1e10,
            maxLtv: maxLtv,
            healthFactor: healthFactor
        });

        console.log("collateralBase", state.collateralBase);
        console.log("debtBase", state.debtBase);
        console.log("maxLtv", state.maxLtv);
        console.log("healthFactor", state.healthFactor);
        console.log("current ltv", ALMFCalcLib.getLtv(state.collateralBase, state.debtBase));
    }

    /// @notice Get maximum LTV for the collateral asset in AAVE, INTERNAL_PRECISION
    function _getMaxLtv(ALMFCalcLib.StaticData memory data) internal view returns (uint maxLtv) {
        IAaveDataProvider dataProvider = IAaveDataProvider(IAaveAddressProvider(data.addressProvider).getPoolDataProvider());
        (, maxLtv,,,,,,,,) = dataProvider.getReserveConfigurationData(data.collateralAsset);
    }

    function totalCollateral(address lendingVault) public view returns (uint) {
        return IAToken(lendingVault).balanceOf(address(this));
    }

    function health(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IFactory.Farm memory farm
    )
    internal
    view
    returns (
        uint ltv,
        uint maxLtv,
        uint leverage,
        uint collateralAmount,
        uint debtAmount,
        uint targetLeveragePercent
    ) {
        console.log("health");
        ALMFCalcLib.StaticData memory data = _getStaticData(platform, $, farm);
        IPool pool = IPool(IAToken(data.lendingVault).POOL());

        // Maximum LTV with 4 decimals
        uint collateralAmountBase;
        uint debtAmountBase;
        (collateralAmountBase, debtAmountBase, , , maxLtv, ) = pool.getUserAccountData(address(this));

        // Current amount of collateral asset (strategy asset)
        collateralAmount = ALMFCalcLib.baseToCollateral(collateralAmountBase, data);

        // Current debt of borrowed asset
        debtAmount = ALMFCalcLib.baseToBorrow(debtAmountBase, data);

        // Current LTV with 4 decimals
        ltv = ALMFCalcLib.getLtv(collateralAmountBase, debtAmountBase);

        // Current leverage multiplier with 4 decimals
        leverage = ALMFCalcLib.ltvToLeverage(ltv);

        // targetLeveragePercent Configurable percent of max leverage with 4 decimals
        uint maxLeverage = ALMFCalcLib.ltvToLeverage(maxLtv);
        uint targetLeverage = (data.minTargetLeverage + data.maxTargetLeverage) / 2;
        targetLeveragePercent = targetLeverage * ALMFCalcLib.INTERNAL_PRECISION / maxLeverage;
    }

    function total(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IFactory.Farm memory farm
    ) external view returns (uint totalValue) {
        ALMFCalcLib.StaticData memory data = _getStaticData(platform, $, farm);
        ALMFCalcLib.State memory state = _getState(data);
        totalValue = calcTotal(state);
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

//region -------------------------------------  Rebalance debt
    function rebalanceDebt(
        address platform,
        uint newLtv,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IFactory.Farm memory farm
    ) internal returns (uint resultLtv) {
        ALMFCalcLib.StaticData memory data = _getStaticData(platform, $, farm);
        ALMFCalcLib.State memory state = _getState(data);

        // here is the math that works:
        // collateral_value - debt_value = real_TVL
        // debt_value * PRECISION / collateral_value = LTV
        // ---
        // new_collateral_value = real_TVL * PRECISION / (PRECISION - LTV)
        // new_debt_value = new_collateral_value * LTV / PRECISION
        // real_TVL is not changed if current strategy balance of collateral is zero

        uint tvlBase = ALMFCalcLib.collateralToBase(StrategyLib.balance(data.collateralAsset), data) + calcTotal(state);
        console.log("rebalanceDebt.tvlPricedInCollateralAsset", tvlBase);
        console.log("rebalanceDebt.newLtv", newLtv);

        uint newCollateralValueBase = tvlBase * ALMFCalcLib.INTERNAL_PRECISION / (ALMFCalcLib.INTERNAL_PRECISION - newLtv);
        uint newDebtAmountBase = newCollateralValueBase * newLtv / ALMFCalcLib.INTERNAL_PRECISION;

        uint debtDiff;
        if (newLtv < ALMFCalcLib.getLtv(state.collateralBase, state.debtBase)) {
            console.log("case 1");
            // need decrease debt and collateral
            $.tempAction = ILeverageLendingStrategy.CurrentAction.DecreaseLtv;

            console.log("ALMFCalcLib.baseToBorrow(state.debtBase, data)", ALMFCalcLib.baseToBorrow(state.debtBase, data));
            debtDiff = ALMFCalcLib.baseToBorrow(state.debtBase - newDebtAmountBase, data);

            $.tempCollateralAmount = (ALMFCalcLib.baseToCollateral(state.collateralBase - newCollateralValueBase, data)) * $.decreaseLtvParam0 / ALMFCalcLib.INTERNAL_PRECISION;
        } else {
            console.log("case 2");
            // need increase debt and collateral
            $.tempAction = ILeverageLendingStrategy.CurrentAction.IncreaseLtv;

            console.log("ALMFCalcLib.baseToBorrow(state.debtBase, data)", ALMFCalcLib.baseToBorrow(state.debtBase, data));
            debtDiff = (ALMFCalcLib.baseToBorrow(newDebtAmountBase - state.debtBase, data)) * $.increaseLtvParam0 / ALMFCalcLib.INTERNAL_PRECISION;
        }

        console.log("rebalanceDebt.debtDiff", debtDiff);

        (address[] memory flashAssets, uint[] memory flashAmounts) = _getFlashLoanAmounts(debtDiff, data.borrowAsset);

        LeverageLendingLib.requestFlashLoan($, flashAssets, flashAmounts);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.None;

        state = _getState(data);
        resultLtv = ALMFCalcLib.getLtv(state.collateralBase, state.debtBase);
    }
//endregion ------------------------------------- Rebalance debt

//region ------------------------------------- Real tvl

    function realTvl(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IFactory.Farm memory farm
    ) public view returns (uint tvl, bool trusted) {
        ALMFCalcLib.StaticData memory data = _getStaticData(platform, $, farm);
        ALMFCalcLib.State memory state = _getState(data);
        return _realTvl(state);
    }

    function _realTvl(ALMFCalcLib.State memory state) internal pure returns (uint tvl, bool trusted) {
        tvl = state.collateralBase - state.debtBase;
        trusted = true;
    }
//endregion ------------------------------------- Real tvl


    function _getDepositAndBorrowAprs(
        address lendingVault,
        address collateralAsset,
        address borrowAsset
    ) internal view returns (uint depositApr, uint borrowApr) {
        IPool pool = IPool(IAToken(lendingVault).POOL());
        IPool.ReserveData memory collateralData = pool.getReserveData(collateralAsset);
        IPool.ReserveData memory borrowData = pool.getReserveData(borrowAsset);

        // liquidityRate and variableBorrowRate are in Ray (1e27)
        // To convert to percentage with 5 decimals (1e5), use:
        // rate(1e27) * 1e5 / 1e27 = rate / 1e22
        depositApr = uint256(collateralData.currentLiquidityRate) * ConstantsLib.DENOMINATOR / 1e27;
        borrowApr = uint256(borrowData.currentVariableBorrowRate) * ConstantsLib.DENOMINATOR / 1e27;
    }

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

    function _ensureLtvValid(ALMFCalcLib.State memory state) internal pure {
        if (state.debtBase != 0) {
            uint ltv = ALMFCalcLib.getLtv(state.collateralBase, state.debtBase);
            require(state.healthFactor > 1e18 && ltv < state.maxLtv, IControllable.IncorrectLtv(ltv));
        }
    }
//endregion ------------------------------------- Internal utils
}
