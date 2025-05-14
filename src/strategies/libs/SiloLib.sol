// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../../lib/forge-std/src/console.sol";
import "../../interfaces/IStrategy.sol";
import {IControllable} from "../../interfaces/IControllable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ILeverageLendingStrategy} from "../../interfaces/ILeverageLendingStrategy.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IPriceReader} from "../../interfaces/IPriceReader.sol";
import {ISiloConfig} from "../../integrations/silo/ISiloConfig.sol";
import {ISiloLens} from "../../integrations/silo/ISiloLens.sol";
import {ISiloOracle} from "../../integrations/silo/ISiloOracle.sol";
import {ISilo} from "../../integrations/silo/ISilo.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StrategyLib} from "./StrategyLib.sol";
import {LeverageLendingLib} from "./LeverageLendingLib.sol";
import {console} from "forge-std/Test.sol";

library SiloLib {
    using SafeERC20 for IERC20;

    /// @dev 100_00 is 1.0 or 100%
    uint public constant INTERNAL_PRECISION = 100_00;

    //region ------------------------------------- Data types
    struct CollateralDebtState {
        uint collateralPrice;
        uint borrowAssetPrice;
        /// @notice Collateral in lending vault + collateral on the strategy balance, in USD
        uint totalCollateralUsd;
        uint borrowAssetUsd;
        uint collateralBalance;
        /// @notice Amount of collateral in the lending vault
        uint collateralAmount;
        uint debtAmount;
        bool trusted;
    }

    struct StateBeforeWithdraw {
        uint collateralBalanceStrategy;
        uint valueWas;
        uint ltv;
        uint maxLtv;
        uint maxLeverage;
        uint targetLeverage;
        uint collateralAmountToWithdraw;
        uint withdrawParam0;
        uint withdrawParam1;
        uint priceCtoB;
    }
    //endregion ------------------------------------- Data types

    function receiveFlashLoan(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address token,
        uint amount,
        uint feeAmount
    ) external {
        address flashLoanVault = $.flashLoanVault;
        if (msg.sender != flashLoanVault) {
            revert IControllable.IncorrectMsgSender();
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.Deposit) {
            console.log('Do Deposit');
            console.log('Balance collateral', IERC20(token).balanceOf(address(this)));
            console.log('Balance borrow', IERC20($.borrowAsset).balanceOf(address(this)));
            console.log("Real collateral", totalCollateral($.lendingVault));
            console.log("Real debt", totalDebt($.borrowingVault));
            console.log("deposit C", amount);

            // token is collateral asset
            uint tempBorrowAmount = $.tempBorrowAmount;

            // supply
            ISilo($.lendingVault).deposit(amount, address(this), ISilo.CollateralType.Collateral);

            console.log('Balance collateral', IERC20(token).balanceOf(address(this)));
            console.log('Balance borrow', IERC20($.borrowAsset).balanceOf(address(this)));
            console.log("Real collateral", totalCollateral($.lendingVault));
            console.log("Real debt", totalDebt($.borrowingVault));
            console.log("borrow", tempBorrowAmount);

            // borrow
            ISilo($.borrowingVault).borrow(tempBorrowAmount, address(this), address(this));

            // swap
            console.log('Balance collateral', IERC20(token).balanceOf(address(this)));
            console.log('Balance borrow', IERC20($.borrowAsset).balanceOf(address(this)));
            console.log("Real collateral", totalCollateral($.lendingVault));
            console.log("Real debt", totalDebt($.borrowingVault));
            console.log("swap B=>C", tempBorrowAmount);
            StrategyLib.swap(platform, $.borrowAsset, token, tempBorrowAmount);

            console.log('Balance collateral', IERC20(token).balanceOf(address(this)));
            console.log('Balance borrow', IERC20($.borrowAsset).balanceOf(address(this)));
            console.log("Real collateral", totalCollateral($.lendingVault));
            console.log("Real debt", totalDebt($.borrowingVault));
            console.log("pay flashloan C", amount + feeAmount);

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            console.log('Balance collateral', IERC20(token).balanceOf(address(this)));
            console.log('Balance borrow', IERC20($.borrowAsset).balanceOf(address(this)));
            console.log("Real collateral", totalCollateral($.lendingVault));
            console.log("Real debt", totalDebt($.borrowingVault));
            console.log("deposit C", StrategyLib.balance(token));

            // supply remaining balance
            ISilo($.lendingVault).deposit(StrategyLib.balance(token), address(this), ISilo.CollateralType.Collateral);

            console.log('Balance collateral', IERC20(token).balanceOf(address(this)));
            console.log('Balance borrow', IERC20($.borrowAsset).balanceOf(address(this)));
            console.log("Real collateral", totalCollateral($.lendingVault));
            console.log("Real debt", totalDebt($.borrowingVault));

            // reset temp vars
            $.tempBorrowAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.Withdraw) {
            console.log('Do Withdraw');
            console.log('Balance collateral', IERC20(token).balanceOf(address(this)));
            console.log('Balance borrow', IERC20($.borrowAsset).balanceOf(address(this)));
            console.log("deposit C", amount);

            // token is borrow asset
            address collateralAsset = $.collateralAsset;
            uint tempCollateralAmount = $.tempCollateralAmount;

            console.log('Balance collateral', IERC20(token).balanceOf(address(this)));
            console.log('Balance borrow', IERC20($.borrowAsset).balanceOf(address(this)));
            console.log("repay C", amount);

            // repay debt
            ISilo($.borrowingVault).repay(amount, address(this));

            // withdraw
            {
                address lendingVault = $.lendingVault;
                uint collateralAmountTotal = totalCollateral(lendingVault);
                collateralAmountTotal -= collateralAmountTotal / 1000;

                console.log('Balance collateral', IERC20(token).balanceOf(address(this)));
                console.log('Balance borrow', IERC20($.borrowAsset).balanceOf(address(this)));
                console.log("withdraw", Math.min(tempCollateralAmount, collateralAmountTotal));

                ISilo(lendingVault).withdraw(
                    Math.min(tempCollateralAmount, collateralAmountTotal),
                    address(this),
                    address(this),
                    ISilo.CollateralType.Collateral
                );
            }

            // swap
            console.log('Balance collateral', IERC20(token).balanceOf(address(this)));
            console.log('Balance borrow', IERC20($.borrowAsset).balanceOf(address(this)));
            console.log("swap C=>B", Math.min(tempCollateralAmount, StrategyLib.balance(collateralAsset)));
            StrategyLib.swap(
                platform, collateralAsset, token, Math.min(tempCollateralAmount, StrategyLib.balance(collateralAsset))
            );

            // pay flash loan
            console.log('Balance collateral', IERC20(token).balanceOf(address(this)));
            console.log('Balance borrow', IERC20($.borrowAsset).balanceOf(address(this)));
            console.log("pay flashloan C", amount + feeAmount);
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // swap unnecessary borrow asset
            console.log('Balance collateral', IERC20(token).balanceOf(address(this)));
            console.log('Balance borrow', IERC20($.borrowAsset).balanceOf(address(this)));
            console.log("swap B=>C", StrategyLib.balance(token));
            StrategyLib.swap(platform, token, collateralAsset, StrategyLib.balance(token));
            console.log("done");

            // reset temp vars
            $.tempCollateralAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.DecreaseLtv) {
            // tokens[0] is collateral asset
            address lendingVault = $.lendingVault;

            // swap
            console.log("swap 4");
            StrategyLib.swap(platform, token, $.borrowAsset, amount);

            // repay
            ISilo($.borrowingVault).repay(StrategyLib.balance($.borrowAsset), address(this));

            // withdraw amount to pay flash loan
            uint toWithdraw = amount + feeAmount - StrategyLib.balance(token);
            ISilo(lendingVault).withdraw(toWithdraw, address(this), address(this), ISilo.CollateralType.Collateral);

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.IncreaseLtv) {
            // tokens[0] is collateral asset
            uint tempBorrowAmount = $.tempBorrowAmount;
            address lendingVault = $.lendingVault;

            // supply
            ISilo($.lendingVault).deposit(amount, address(this), ISilo.CollateralType.Collateral);

            // borrow
            ISilo($.borrowingVault).borrow(tempBorrowAmount, address(this), address(this));

            // swap
            console.log("swap 5");
            StrategyLib.swap(platform, $.borrowAsset, token, tempBorrowAmount);

            // withdraw or supply if need
            uint bal = StrategyLib.balance(token);
            uint remaining = bal < (amount + feeAmount) ? amount + feeAmount - bal : 0;
            if (remaining != 0) {
                ISilo(lendingVault).withdraw(remaining, address(this), address(this), ISilo.CollateralType.Collateral);
            } else {
                uint toSupply = bal - (amount + feeAmount);
                ISilo($.lendingVault).deposit(toSupply, address(this), ISilo.CollateralType.Collateral);
            }

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // reset temp vars
            $.tempBorrowAmount = 0;
        }

        (uint ltv,, uint leverage,,,) = health(platform, $);
        emit ILeverageLendingStrategy.LeverageLendingHealth(ltv, leverage);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.None;
    }

    function health(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $
    )
        public
        view
        returns (
            uint ltv,
            uint maxLtv,
            uint leverage,
            uint collateralAmount,
            uint debtAmount,
            uint targetLeveragePercent
        )
    {
        address lendingVault = $.lendingVault;
        address collateralAsset = $.collateralAsset;

        ltv = ISiloLens($.helper).getLtv(lendingVault, address(this));
        ltv = ltv * INTERNAL_PRECISION / 1e18;

        collateralAmount = StrategyLib.balance(collateralAsset) + totalCollateral(lendingVault);
        debtAmount = totalDebt($.borrowingVault);

        IPriceReader priceReader = IPriceReader(IPlatform(platform).priceReader());
        (uint _realTvl,) = realTvl(platform, $);
        (uint collateralPrice,) = priceReader.getPrice(collateralAsset);
        uint collateralUsd = collateralAmount * collateralPrice / 10 ** IERC20Metadata(collateralAsset).decimals();
        leverage = collateralUsd * INTERNAL_PRECISION / _realTvl;

        targetLeveragePercent = $.targetLeveragePercent;

        (maxLtv,,) = getLtvData(lendingVault, targetLeveragePercent);

        console.log("health");
        console.log("ltv", ltv);
        console.log("collateralAmountBalance", StrategyLib.balance(collateralAsset));
        console.log("totalCollateralLendingVault", totalCollateral(lendingVault));
        console.log("collateralAmount total", collateralAmount);
        console.log("debtAmount", debtAmount);
        console.log("_realTvl", _realTvl);
        console.log("collateralPrice", collateralPrice);
        console.log("collateralUsd", collateralUsd);
        console.log("leverage", leverage);
    }

    function realTvl(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $
    ) public view returns (uint tvl, bool trusted) {
        console.log("realTvl");
        SiloAdvancedLib.CollateralDebtState memory debtState =
                        getDebtState(platform, $.lendingVault, $.collateralAsset, $.borrowAsset, $.borrowingVault);
        tvl = debtState.totalCollateralUsd - debtState.borrowAssetUsd;
        trusted = debtState.trusted;
        console.log("tvl", tvl);
    }

    function getDebtState(
        address platform,
        address lendingVault,
        address collateralAsset,
        address borrowAsset,
        address borrowingVault
    ) public view returns (CollateralDebtState memory data) {
        bool collateralPriceTrusted;
        bool borrowAssetPriceTrusted;

        IPriceReader priceReader = IPriceReader(IPlatform(platform).priceReader());

        data.collateralAmount = totalCollateral(lendingVault);
        data.collateralBalance = StrategyLib.balance(collateralAsset);
        (data.collateralPrice, collateralPriceTrusted) = priceReader.getPrice(collateralAsset);
        data.totalCollateralUsd = (data.collateralAmount + data.collateralBalance) * data.collateralPrice
            / 10 ** IERC20Metadata(collateralAsset).decimals();

        data.debtAmount = totalDebt(borrowingVault);
        (data.borrowAssetPrice, borrowAssetPriceTrusted) = priceReader.getPrice(borrowAsset);
        data.borrowAssetUsd = data.debtAmount * data.borrowAssetPrice / 10 ** IERC20Metadata(borrowAsset).decimals();

        data.trusted = collateralPriceTrusted && borrowAssetPriceTrusted;


        console.log("collateralPrice", data.collateralPrice);
        console.log("borrowAssetPrice", data.borrowAssetPrice);
        console.log("collateralAmount", data.collateralAmount);
        console.log("collateralBalance", data.collateralBalance);
        console.log("totalCollateral", data.collateralAmount + data.collateralBalance);
        console.log("debtAmount", data.debtAmount);
        console.log("collateralUsd", data.totalCollateralUsd);
        console.log("borrowAssetUsd", data.borrowAssetUsd);

        return data;
    }

    function getPrices(address lendVault, address debtVault) public view returns (uint priceCtoB, uint priceBtoC) {
        ISiloConfig siloConfig = ISiloConfig(ISilo(lendVault).config());
        ISiloConfig.ConfigData memory collateralConfig = siloConfig.getConfig(lendVault);
        address collateralOracle = collateralConfig.solvencyOracle;
        ISiloConfig.ConfigData memory borrowConfig = siloConfig.getConfig(debtVault);
        address borrowOracle = borrowConfig.solvencyOracle;
        if (collateralOracle != address(0) && borrowOracle == address(0)) {
            priceCtoB = ISiloOracle(collateralOracle).quote(
                10 ** IERC20Metadata(collateralConfig.token).decimals(), collateralConfig.token
            );
            priceBtoC = 1e18 * 1e18 / priceCtoB;
        } else if (collateralOracle == address(0) && borrowOracle != address(0)) {
            priceBtoC =
                ISiloOracle(borrowOracle).quote(10 ** IERC20Metadata(borrowConfig.token).decimals(), borrowConfig.token);
            priceCtoB = 1e18 * 1e18 / priceBtoC;
        } else {
            revert("Not implemented yet");
        }
    }

    /// @dev LTV data
    /// @return maxLtv Max LTV with 18 decimals
    /// @return maxLeverage Max leverage multiplier with 4 decimals
    /// @return targetLeverage Target leverage multiplier with 4 decimals
    function getLtvData(
        address lendingVault,
        uint targetLeveragePercent
    ) public view returns (uint maxLtv, uint maxLeverage, uint targetLeverage) {
        address configContract = ISilo(lendingVault).config();
        ISiloConfig.ConfigData memory config = ISiloConfig(configContract).getConfig(lendingVault);
        maxLtv = config.maxLtv;
        maxLeverage = 1e18 * INTERNAL_PRECISION / (1e18 - maxLtv);
        targetLeverage = maxLeverage * targetLeveragePercent / INTERNAL_PRECISION;

        console.log("maxLtv", maxLtv);
        console.log("maxLeverage", maxLeverage);
        console.log("targetLeverage", targetLeverage);
    }

    function calcTotal(ILeverageLendingStrategy.LeverageLendingAddresses memory v) public view returns (uint) {
        (, uint priceBtoC) = getPrices(v.lendingVault, v.borrowingVault);
        uint borrowedAmountPricedInCollateral = totalDebt(v.borrowingVault) * priceBtoC / 1e18;
        return totalCollateral(v.lendingVault) - borrowedAmountPricedInCollateral;
    }

    function totalCollateral(address lendingVault) public view returns (uint) {
        return IERC4626(lendingVault).convertToAssets(StrategyLib.balance(lendingVault));
    }

    function totalDebt(address borrowingVault) public view returns (uint) {
        return ISilo(borrowingVault).maxRepay(address(this));
    }

    //region ------------------------------------- Deposit
    function depositAssets(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IStrategy.StrategyBaseStorage storage $base,
        address[] memory _assets,
        uint[] memory amounts
    ) external returns (uint value) {
        ILeverageLendingStrategy.LeverageLendingAddresses memory v = getLeverageLendingAddresses($);
        uint valueWas = StrategyLib.balance(_assets[0]) + calcTotal(v);
        _deposit($, v, _assets, amounts[0]);
        uint valueNow = StrategyLib.balance(_assets[0]) + calcTotal(v);
        console.log("valueWas", valueWas);
        console.log("valueNow", valueNow);

        if (valueNow > valueWas) {
            // deposit profit
            value = amounts[0] + (valueNow - valueWas);
        } else {
            // deposit loss
            value = amounts[0] - (valueWas - valueNow);
        }
        console.log("value", value);

        $base.total += value;
        console.log("$base.total", $base.total);
    }

    /// @param _assets [collateral asset]
    /// @param amountToDeposit Amount to deposit in collateral asset
    function _deposit(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        address[] memory _assets,
        uint amountToDeposit
    ) internal {
        (uint maxLtv,, uint targetLeverage) = getLtvData(v.lendingVault, $.targetLeveragePercent);

        uint[] memory flashAmounts = new uint[](1);
        flashAmounts[0] = amountToDeposit * targetLeverage / INTERNAL_PRECISION;
        console.log("flashAmountsC", flashAmounts[0]);

        (uint priceCtoB,) = getPrices(v.lendingVault, v.borrowingVault);

        $.tempBorrowAmount = (flashAmounts[0] * maxLtv / 1e18) * priceCtoB / 1e18 - 2;
        console.log("tempBorrowAmount", $.tempBorrowAmount);
        $.tempAction = ILeverageLendingStrategy.CurrentAction.Deposit;
        LeverageLendingLib.requestFlashLoan($, _assets, flashAmounts);
    }
    //endregion ------------------------------------- Deposit

    //region ------------------------------------- Withdraw
    function withdrawAssets(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IStrategy.StrategyBaseStorage storage $base,
        uint value,
        address receiver
    ) internal returns (uint[] memory amountsOut) {
        ILeverageLendingStrategy.LeverageLendingAddresses memory v = getLeverageLendingAddresses($);
        SiloAdvancedLib.StateBeforeWithdraw memory state = _getStateBeforeWithdraw(platform, $, v);

        // ---------------------- withdraw from the lending vault - only if amount on the balance is not enough
        if (value > state.collateralBalanceStrategy) {
            // it's too dangerous to ask value - state.collateralBalanceStrategy
            // because current balance is used in multiple places inside receiveFlashLoan
            // so we ask to withdraw full required amount
            withdrawFromLendingVault(platform, $, v, state, value);
        }

        // ---------------------- Transfer required amount to the user, update base.total
        uint bal = StrategyLib.balance(v.collateralAsset);
        uint valueNow = bal + calcTotal(v);

        amountsOut = new uint[](1);
        if (state.valueWas > valueNow) {
            amountsOut[0] = Math.min(value - (state.valueWas - valueNow), bal);
        } else {
            amountsOut[0] = Math.min(value + (valueNow - state.valueWas), bal);
        }
        console.log("bal", bal);
        console.log("transfer C", amountsOut[0]);
        console.log("valueWas", state.valueWas);
        console.log("valueNow", valueNow);
        console.log("value", value);

        if (receiver != address(this)) {
            IERC20(v.collateralAsset).safeTransfer(receiver, amountsOut[0]);
        }

        $base.total -= value;
        console.log("$base.total ", $base.total);

        // ---------------------- Deposit the amount ~ value
        if (state.withdrawParam1 > INTERNAL_PRECISION) {
            uint balance = StrategyLib.balance(v.collateralAsset);
            if (balance != 0) {
                SiloLib._deposit($, v, Math.min(state.withdrawParam1 * value / INTERNAL_PRECISION, balance));
            }
        }
    }

    function withdrawFromLendingVault(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        StateBeforeWithdraw memory state,
        uint value
    ) internal {
        (,, uint leverage,,,) = health(platform, $);

        SiloAdvancedLib.CollateralDebtState memory debtState = getDebtState(platform, v.lendingVault, v.collateralAsset, v.borrowAsset, v.borrowingVault);

        if (0 == debtState.debtAmount) {
            // zero debt, positive collateral - we can just withdraw required amount
            uint amountToWithdraw = Math.min(
                value > debtState.collateralBalance ? value - debtState.collateralBalance : 0,
                debtState.collateralAmount
            );
            if (amountToWithdraw != 0) {
                ISilo(v.lendingVault).withdraw(
                    amountToWithdraw, address(this), address(this), ISilo.CollateralType.Collateral
                );
            }
        } else {
            uint valueToWithdraw = value;
            if (leverage < state.targetLeverage && state.targetLeverage > 1) {
                // Can we increase the debt without increasing collateral?
                uint addDebtUsd = debtState.borrowAssetUsd
                < debtState.totalCollateralUsd * (state.targetLeverage - 1) / state.targetLeverage
                    ? debtState.totalCollateralUsd * (state.targetLeverage - 1) / state.targetLeverage
                    - debtState.borrowAssetUsd
                    : 0;
                uint valueInUsd =
                    value * debtState.collateralPrice / (10 ** IERC20Metadata(v.collateralAsset).decimals());

                // We can increase debt, but we shouldn't increase it too fast
                // so, let's limit the increasing by x2
                // We need to get collateral value valueInUsd
                // But swaps are unpredictable, so let's try to get more collateral i.e. x1.5
                // todo 150_00 and 2 => to constant? to universal param?
                if (150_00 * valueInUsd / INTERNAL_PRECISION < addDebtUsd / 2) {
                    if (_withdrawThroughIncreasingLtv($, v, state, debtState, value, leverage)) {
                        valueToWithdraw = 0;
                    }
                }
            }

            if (valueToWithdraw != 0) {
                _defaultWithdraw($, v, state, valueToWithdraw);
            }
        }
    }

    /// @notice Default withdraw procedure (leverage is a bit decreased)
    function _defaultWithdraw(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        StateBeforeWithdraw memory state,
        uint value
    ) internal {
        // repay debt and withdraw
        // we use maxLeverage and maxLtv, so result ltv will reduce
        uint collateralAmountToWithdraw = value * state.maxLeverage / INTERNAL_PRECISION;

        uint[] memory flashAmounts = new uint[](1);
        flashAmounts[0] = collateralAmountToWithdraw * state.maxLtv / 1e18 * state.priceCtoB * state.withdrawParam0
            * (10 ** IERC20Metadata(v.borrowAsset).decimals()) / 1e18 // priceCtoB has decimals 1e18
            / INTERNAL_PRECISION // withdrawParam0
            / (10 ** IERC20Metadata(v.collateralAsset).decimals());
        address[] memory flashAssets = new address[](1);
        flashAssets[0] = $.borrowAsset;

        $.tempCollateralAmount = collateralAmountToWithdraw;
        $.tempAction = ILeverageLendingStrategy.CurrentAction.Withdraw;
        LeverageLendingLib.requestFlashLoan($, flashAssets, flashAmounts);
    }

    /// @param value Full amount of the collateral asset that the user is asking to withdraw
    function _withdrawThroughIncreasingLtv(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        StateBeforeWithdraw memory state,
        SiloAdvancedLib.CollateralDebtState memory debtState,
        uint value,
        uint leverage
    ) internal returns (bool) {
        // --------- Calculate new leverage after deposit {value} with target leverage and withdraw {value} on balance
        int leverageNew = _calculateNewLeverage(v, state, debtState, value);

        if (
            leverageNew <= 0 || uint(leverageNew) > state.maxLeverage * 1e18 / INTERNAL_PRECISION
            || uint(leverageNew) < leverage * 1e18 / INTERNAL_PRECISION
        ) {
            return false; // use default withdraw
        }

        uint priceCtoB;
        (priceCtoB,) = getPrices(v.lendingVault, v.borrowingVault);

        // --------- Calculate debt to add
        uint debtDiff = (value * uint(leverageNew)) / 1e18 // leverageNew
            * priceCtoB * state.maxLtv / 1e18 // ltv
            * (10 ** IERC20Metadata(v.borrowAsset).decimals()) / (10 ** IERC20Metadata(v.collateralAsset).decimals()) / 1e18; // priceCtoB has decimals 18

        address[] memory flashAssets = new address[](1);
        flashAssets[0] = v.borrowAsset;
        uint[] memory flashAmounts = new uint[](1);
        flashAmounts[0] = debtDiff * $.increaseLtvParam0 / INTERNAL_PRECISION;

        // --------- Increase ltv: limit spending from both balances
        $.tempCollateralAmount = value * uint(leverageNew);
        $.tempAction = ILeverageLendingStrategy.CurrentAction.IncreaseLtv;
        LeverageLendingLib.requestFlashLoan($, flashAssets, flashAmounts);

        // --------- Withdraw value from landing vault to the strategy balance
        ISilo(v.lendingVault).withdraw(value, address(this), address(this), ISilo.CollateralType.Collateral);

        return true;
    }

    /// @notice Calculate result leverage in assumption that we increase leverage and extract {value} of collateral
    function _calculateNewLeverage(
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        SiloAdvancedLib.StateBeforeWithdraw memory state,
        SiloAdvancedLib.CollateralDebtState memory debtState,
        uint value
    ) internal view returns (int leverageNew) {
        // L_initial - current leverage
        // ltv = max ltv
        // X - collateral amount to withdraw
        // L_new = new leverage (it must be > current leverage)
        // C_add - new required collateral = L_new * X
        // D_inc - increment of the debt = ltv * C_add = ltv * L_new * X
        // C_new = new collateral = C - X + C_add
        // D_new = new debt = D + D_inc
        // The math:
        //      L_new = C_new / (C_new - D_new)
        //      L_new = (C - X + L_new * X) / (C - X - D + L_new * X - ltv * L_new * X)
        //      L_new^2 * [X * (1 - ltv)] + L_new * (C - D - 2X) - (C - X) = 0
        // Solve square equation
        //      A = X (1 - ltv), B = C - D - 2X, C_quad = -(C - X)
        //      L_new = [-B + sqrt(B^2 - 4*A*C_quad)] / 2 A
        uint xUsd = value * debtState.collateralPrice / (10 ** IERC20Metadata(v.collateralAsset).decimals());

        int a = int(xUsd * (1e18 - state.maxLtv) / 1e18);
        int b = int(debtState.totalCollateralUsd) - int(debtState.borrowAssetUsd) - int(2 * xUsd);
        int cQuad = -(int(debtState.totalCollateralUsd) - int(xUsd));

        int det2 = b * b - 4 * a * cQuad;
        if (det2 < 0) return 0;

        leverageNew = (-b + int(Math.sqrt(uint(det2)))) * 1e18 / (2 * a);

        return leverageNew;
    }

    function _getStateBeforeWithdraw(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v
    ) public view returns (StateBeforeWithdraw memory state) {
        state.collateralBalanceStrategy = StrategyLib.balance(v.collateralAsset);
        state.valueWas = state.collateralBalanceStrategy + calcTotal(v);
        (state.ltv,,,,,) = health(platform, $);
        (state.maxLtv, state.maxLeverage, state.targetLeverage) = getLtvData(v.lendingVault, $.targetLeveragePercent);
        (state.priceCtoB,) = getPrices(v.lendingVault, v.borrowingVault);
        state.withdrawParam0 = $.withdrawParam0;
        state.withdrawParam1 = $.withdrawParam1;
        if (state.withdrawParam0 == 0) state.withdrawParam0 = 100_00;
        if (state.withdrawParam1 == 0) state.withdrawParam1 = 100_00;

        return state;
    }
    //endregion ------------------------------------- Withdraw

    //region ------------------------------------- Internal
    function getLeverageLendingAddresses(ILeverageLendingStrategy.LeverageLendingBaseStorage storage $)
        internal
        view
        returns (ILeverageLendingStrategy.LeverageLendingAddresses memory)
    {
        return ILeverageLendingStrategy.LeverageLendingAddresses({
            collateralAsset: $.collateralAsset,
            borrowAsset: $.borrowAsset,
            lendingVault: $.lendingVault,
            borrowingVault: $.borrowingVault
        });
    }
    //endregion ------------------------------------- Internal
}
