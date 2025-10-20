// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IStrategy} from "../../interfaces/IStrategy.sol";
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

library SiloLib {
    using SafeERC20 for IERC20;

    /// @dev 100_00 is 1.0 or 100%
    uint public constant INTERNAL_PRECISION = 100_00;

    /// @notice Price impact tolerance. Denominator is 100_000.
    uint private constant PRICE_IMPACT_TOLERANCE = 1000;

    uint private constant MAX_COUNT_LEVERAGE_SEARCH_ITERATIONS = 20;

    uint private constant PRICE_IMPACT_DENOMINATOR = 100_000;

    uint private constant SEARCH_LEVERAGE_TOLERANCE = 1e16; // 0.01 tolerance scaled by 1e18

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
        uint withdrawParam2;
        uint priceCtoB;
    }

    /// @notice Defines the configuration parameters for leverage calculation.
    struct LeverageCalcParams {
        /// @notice Amount of collateral to withdraw (in USD).
        uint xWithdrawAmount;
        /// @notice Current collateral in the user's strategy (in USD).
        uint currentCollateralAmount;
        /// @notice Current debt (in USD).
        uint currentDebtAmount;
        /// @notice Initial balance of collateral asset available, in USD.
        uint initialBalanceC;
        /// @notice Swap efficiency factor (0...1], scaled by `scale` (e.g., 0.9998 is 0.9998 * scale).
        uint alphaScaled;
        /// @notice Flash loan fee rate, scaled by `scale` (e.g., for a 0.2% fee, the rate is 0.002, which would be passed as 2e15 if scale is 1e18).
        uint betaRateScaled;
    }

    //endregion ------------------------------------- Data types

    function receiveFlashLoan(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address token,
        uint amount,
        uint feeAmount
    ) external {
        address flashLoanVault = _getFlashLoanAddress($, token);
        if (msg.sender != flashLoanVault) {
            revert IControllable.IncorrectMsgSender();
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.Deposit) {
            //  flash amount is collateral
            // token is collateral asset
            uint tempBorrowAmount = $.tempBorrowAmount;

            // supply
            ISilo($.lendingVault).deposit(amount, address(this), ISilo.CollateralType.Collateral);

            // borrow
            ISilo($.borrowingVault).borrow(tempBorrowAmount, address(this), address(this));

            // swap
            StrategyLib.swap(platform, $.borrowAsset, token, tempBorrowAmount);

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // supply remaining balance
            ISilo($.lendingVault).deposit(StrategyLib.balance(token), address(this), ISilo.CollateralType.Collateral);

            // reset temp vars
            $.tempBorrowAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.Withdraw) {
            // flash is in borrow asset
            // token is borrow asset
            address collateralAsset = $.collateralAsset;
            uint tempCollateralAmount = $.tempCollateralAmount;

            // repay debt
            ISilo($.borrowingVault).repay(amount, address(this));

            // withdraw
            {
                address lendingVault = $.lendingVault;
                uint collateralAmountTotal = totalCollateral(lendingVault);
                collateralAmountTotal -= collateralAmountTotal / 1000;

                ISilo(lendingVault)
                    .withdraw(
                        Math.min(tempCollateralAmount, collateralAmountTotal),
                        address(this),
                        address(this),
                        ISilo.CollateralType.Collateral
                    );
            }

            // swap
            StrategyLib.swap(
                platform, collateralAsset, token, Math.min(tempCollateralAmount, StrategyLib.balance(collateralAsset))
            );

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // swap unnecessary borrow asset
            StrategyLib.swap(platform, token, collateralAsset, StrategyLib.balance(token));

            // reset temp vars
            $.tempCollateralAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.DecreaseLtv) {
            // tokens[0] is collateral asset
            address lendingVault = $.lendingVault;

            // swap
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
            StrategyLib.swap(platform, $.borrowAsset, token, tempBorrowAmount, PRICE_IMPACT_TOLERANCE);

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
    }

    function rebalanceDebt(
        address platform,
        uint newLtv,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $
    ) external returns (uint resultLtv) {
        (uint ltv, uint maxLtv,, uint collateralAmount,,) = health(platform, $);

        ILeverageLendingStrategy.LeverageLendingAddresses memory v = getLeverageLendingAddresses($);

        uint tvlPricedInCollateralAsset = calcTotal(v);

        // here is the math that works:
        // collateral_value - debt_value = real_TVL
        // debt_value * PRECISION / collateral_value = LTV
        // ---
        // collateral_value = real_TVL * PRECISION / (PRECISION - LTV)

        uint newCollateralValue = tvlPricedInCollateralAsset * INTERNAL_PRECISION / (INTERNAL_PRECISION - newLtv);
        address[] memory flashAssets = new address[](1);
        flashAssets[0] = v.collateralAsset;
        uint[] memory flashAmounts = new uint[](1);

        if (newLtv < ltv) {
            $.tempAction = ILeverageLendingStrategy.CurrentAction.DecreaseLtv;

            // need decrease debt and collateral
            uint collateralDiff = collateralAmount - newCollateralValue;
            flashAmounts[0] = collateralDiff;
        } else {
            $.tempAction = ILeverageLendingStrategy.CurrentAction.IncreaseLtv;

            // need increase debt and collateral
            uint collateralDiff = newCollateralValue - collateralAmount;
            (uint priceCtoB,) = getPrices(v.lendingVault, v.borrowingVault);
            flashAmounts[0] = collateralDiff;
            {
                // use standalone variable to avoid warning "multiplication should occur before division to avoid loss of precision" below
                uint tempAmount = (flashAmounts[0] * maxLtv / 1e18);
                $.tempBorrowAmount = tempAmount * priceCtoB / 1e18 - 2;
            }
        }

        LeverageLendingLib.requestFlashLoanExplicit(
            ILeverageLendingStrategy.FlashLoanKind($.flashLoanKind), $.flashLoanVault, flashAssets, flashAmounts
        );

        $.tempAction = ILeverageLendingStrategy.CurrentAction.None;
        (resultLtv,,,,,) = health(platform, $);
    }

    function realTvl(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $
    ) public view returns (uint tvl, bool trusted) {
        CollateralDebtState memory debtState = getDebtState(
            platform, $.lendingVault, $.collateralAsset, $.borrowAsset, $.borrowingVault
        );
        tvl = debtState.totalCollateralUsd - debtState.borrowAssetUsd;
        trusted = debtState.trusted;
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
        data.totalCollateralUsd = (data.collateralAmount + data.collateralBalance) * data.collateralPrice / 10
            ** IERC20Metadata(collateralAsset).decimals();

        data.debtAmount = totalDebt(borrowingVault);
        (data.borrowAssetPrice, borrowAssetPriceTrusted) = priceReader.getPrice(borrowAsset);
        data.borrowAssetUsd = data.debtAmount * data.borrowAssetPrice / 10 ** IERC20Metadata(borrowAsset).decimals();

        data.trusted = collateralPriceTrusted && borrowAssetPriceTrusted;

        return data;
    }

    function getPrices(address lendVault, address debtVault) public view returns (uint priceCtoB, uint priceBtoC) {
        ISiloConfig siloConfig = ISiloConfig(ISilo(lendVault).config());
        ISiloConfig.ConfigData memory collateralConfig = siloConfig.getConfig(lendVault);
        address collateralOracle = collateralConfig.solvencyOracle;
        ISiloConfig.ConfigData memory borrowConfig = siloConfig.getConfig(debtVault);
        address borrowOracle = borrowConfig.solvencyOracle;
        if (collateralOracle != address(0) && borrowOracle == address(0)) {
            priceCtoB = ISiloOracle(collateralOracle)
                .quote(10 ** IERC20Metadata(collateralConfig.token).decimals(), collateralConfig.token);
            priceBtoC = 1e18 * 1e18 / priceCtoB;
        } else if (collateralOracle == address(0) && borrowOracle != address(0)) {
            priceBtoC = ISiloOracle(borrowOracle)
                .quote(10 ** IERC20Metadata(borrowConfig.token).decimals(), borrowConfig.token);
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

        if (valueNow > valueWas) {
            // deposit profit
            value = amounts[0] + (valueNow - valueWas);
        } else {
            // deposit loss
            value = amounts[0] - (valueWas - valueNow);
        }

        $base.total += value;
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

        (uint priceCtoB,) = getPrices(v.lendingVault, v.borrowingVault);

        {
            // use standalone variable to avoid warning "multiplication should occur before division to avoid loss of precision" below
            uint tempAmount = (flashAmounts[0] * maxLtv / 1e18);
            $.tempBorrowAmount = tempAmount * priceCtoB / 1e18 - 2;
        }
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
    ) external returns (uint[] memory amountsOut) {
        ILeverageLendingStrategy.LeverageLendingAddresses memory v = getLeverageLendingAddresses($);
        StateBeforeWithdraw memory state = _getStateBeforeWithdraw(platform, $, v);

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

        if (receiver != address(this)) {
            IERC20(v.collateralAsset).safeTransfer(receiver, amountsOut[0]);
        }

        $base.total -= value;

        // ---------------------- Deposit the amount ~ value
        if (state.withdrawParam1 > INTERNAL_PRECISION) {
            _depositAfterWithdraw($, v, state.withdrawParam1, value);
        }
    }

    function _depositAfterWithdraw(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        uint withdrawParam1,
        uint value
    ) internal {
        uint balance = StrategyLib.balance(v.collateralAsset);

        // workaround dust problems and error LessThenThreshold
        uint maxAmountToWithdraw = withdrawParam1 * value / INTERNAL_PRECISION;
        if (balance > maxAmountToWithdraw * 100 / INTERNAL_PRECISION) {
            address[] memory assets = new address[](1);
            assets[0] = v.collateralAsset;
            SiloLib._deposit($, v, assets, Math.min(maxAmountToWithdraw, balance));
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

        CollateralDebtState memory debtState =
            getDebtState(platform, v.lendingVault, v.collateralAsset, v.borrowAsset, v.borrowingVault);

        if (0 == debtState.debtAmount) {
            // zero debt, positive collateral - we can just withdraw required amount
            uint amountToWithdraw = Math.min(
                value > debtState.collateralBalance ? value - debtState.collateralBalance : 0,
                debtState.collateralAmount
            );
            if (amountToWithdraw != 0) {
                ISilo(v.lendingVault)
                    .withdraw(amountToWithdraw, address(this), address(this), ISilo.CollateralType.Collateral);
            }
        } else {
            // withdrawParam2 allows to disable withdraw through increasing ltv if leverage is near to target
            if (
                leverage >= state.targetLeverage * state.withdrawParam2 / INTERNAL_PRECISION
                    || !_withdrawThroughIncreasingLtv($, v, state, debtState, value, leverage)
            ) {
                _defaultWithdraw($, v, state, value);
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

        address universalAddress1 = $.universalAddress1;

        $.tempCollateralAmount = collateralAmountToWithdraw;
        $.tempAction = ILeverageLendingStrategy.CurrentAction.Withdraw;
        LeverageLendingLib.requestFlashLoanExplicit(
            ILeverageLendingStrategy.FlashLoanKind($.flashLoanKind),
            universalAddress1 == address(0) ? $.flashLoanVault : universalAddress1,
            flashAssets,
            flashAmounts
        );
    }

    /// @param value Full amount of the collateral asset that the user is asking to withdraw
    function _withdrawThroughIncreasingLtv(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        StateBeforeWithdraw memory state,
        CollateralDebtState memory debtState,
        uint value,
        uint leverage
    ) internal returns (bool) {
        // --------- Calculate new leverage after deposit {value} with target leverage and withdraw {value} on balance
        uint d = (10 ** IERC20Metadata(v.collateralAsset).decimals());
        LeverageCalcParams memory config = LeverageCalcParams({
            xWithdrawAmount: value * debtState.collateralPrice / d,
            currentCollateralAmount: debtState.totalCollateralUsd,
            currentDebtAmount: debtState.borrowAssetUsd,
            initialBalanceC: state.collateralBalanceStrategy * debtState.collateralPrice / d,
            alphaScaled: 1e18 * (PRICE_IMPACT_DENOMINATOR - PRICE_IMPACT_TOLERANCE) / PRICE_IMPACT_DENOMINATOR,
            betaRateScaled: 0 // assume no flash fee
        });

        int leverageNew = int(calculateNewLeverage(config, state.ltv, state.maxLtv));

        if (leverageNew <= 0 || uint(leverageNew) > state.targetLeverage || uint(leverageNew) < leverage) {
            return false; // use default withdraw
        }

        uint priceCtoB;
        (priceCtoB,) = getPrices(v.lendingVault, v.borrowingVault);

        // --------- Calculate required flash amount of collateral
        address[] memory flashAssets = new address[](1);
        flashAssets[0] = v.collateralAsset;
        uint[] memory flashAmounts = new uint[](1);
        flashAmounts[0] = value * uint(leverageNew) / INTERNAL_PRECISION;

        // --------- Increase ltv
        $.tempBorrowAmount = flashAmounts[0] * priceCtoB // no multiplication on ltv here
            * (10 ** IERC20Metadata(v.borrowAsset).decimals()) / (10 ** IERC20Metadata(v.collateralAsset).decimals())
            / 1e18; // priceCtoB has decimals 18
        $.tempAction = ILeverageLendingStrategy.CurrentAction.IncreaseLtv;
        LeverageLendingLib.requestFlashLoan($, flashAssets, flashAmounts);

        // --------- Withdraw value from landing vault to the strategy balance
        ISilo(v.lendingVault).withdraw(value, address(this), address(this), ISilo.CollateralType.Collateral);

        return true;
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
        state.withdrawParam2 = $.withdrawParam2;
        if (state.withdrawParam0 == 0) state.withdrawParam0 = 100_00;
        if (state.withdrawParam1 == 0) state.withdrawParam1 = 100_00;

        return state;
    }

    /// @notice Calculates equilibrium leverage using an iterative approach.
    /// All percentage/rate parameters (ltvScaled, alphaScaled, betaRateScaled) are expected to be scaled by the 'scale' constant.
    /// Amounts (xWithdrawAmount, currentCollateralAmount, etc.) are expected in USD.
    /// Leverage values are also handled as scaled integers.
    /// @param ltv Current value of LTV
    /// @param maxLtv Max allowed LTV
    /// @return resultLeverage The calculated result leverage, decimals INTERNAL_PRECISION
    function calculateNewLeverage(
        LeverageCalcParams memory config,
        uint ltv,
        uint maxLtv
    ) public pure returns (uint resultLeverage) {
        uint optimalLeverage = _findEquilibriumLeverage(
            config,
            1e18 * 1e18 / (1e18 - ltv), // current leverage is the low bound for the leverage search range
            1e18 * 1e18 / (1e18 - maxLtv), // upper bound for the leverage search range
            SEARCH_LEVERAGE_TOLERANCE
        );

        resultLeverage =
            optimalLeverage == 0 ? 0 : INTERNAL_PRECISION * _fullLeverageCalculation(config, optimalLeverage) / 1e18;
    }

    /// @dev Internal function to calculate resulting leverage for a given `leverageNewScaled`.
    /// Mirrors the corrected Python `full_leverage_calculation`.
    /// @param config The configuration parameters.
    /// @param leverageNewScaled The guessed new leverage, scaled 1e18
    /// @return resultLeverageScaled The calculated resulting leverage, scaled by 1e18
    function _fullLeverageCalculation(
        LeverageCalcParams memory config,
        uint leverageNewScaled
    ) internal pure returns (uint resultLeverageScaled) {
        if (leverageNewScaled == 0) {
            return 0;
        }
        // F = L_new * config.xWithdrawAmount (collateral amount borrowed via flash loan)
        uint fAmount = (leverageNewScaled * config.xWithdrawAmount) / 1e18;

        // New collateral amount after applying all operations
        // C_new = CC + F + C_delta - X, C_delta = C1 - F1 (can be negative)
        // C1 = config.initialBalanceC + F * ltv * alpha (collateral balance on hand after swap)
        // F1 = total to return for flash loan = F + F_delta, where F_delta = beta_rate * F (flash fee)
        int cNew = int(config.currentCollateralAmount) + int(fAmount)
            + (int(config.initialBalanceC + fAmount * config.alphaScaled / 1e18)
                - int(fAmount + (fAmount * config.betaRateScaled) / 1e18)) - int(config.xWithdrawAmount);

        if (cNew < 0) {
            return 0; // Resulting cNewAmount would be negative
        }

        // New debt = initial debt + F * ltv
        uint dNewAmount = config.currentDebtAmount + fAmount;

        // Check for insolvency: cNewAmount must be greater than dNewAmount for positive, defined leverage.
        if (uint(cNew) <= dNewAmount) {
            return 0; // Leverage is undefined, zero, or not positive
        }

        // resultLeverageScaled = new collateral / (new collateral - new debt)
        return (uint(cNew) * 1e18) / (uint(cNew) - dNewAmount);
    }

    /// @notice Finds the equilibrium leverage using an iterative binary search approach.
    /// @param config The configuration parameters.
    /// @param lowScaled The lower bound for the leverage search range, decimals 18
    /// @param highScaled The upper bound for the leverage search range, decimals 18
    /// @param toleranceScaled The tolerance for convergence, scaled by `scale` (e.g., for 0.01 tolerance, pass 0.01 * scale = 1e16).
    /// @return equilibriumLeverage The equilibrium leverage found. Decimals are equal to the decimals of low/high.
    /// Returns 0 if not converged or an error occurred during calculation.
    function _findEquilibriumLeverage(
        LeverageCalcParams memory config,
        uint lowScaled,
        uint highScaled,
        uint toleranceScaled
    ) internal pure returns (uint equilibriumLeverage) {
        // Binary search boundaries
        uint iterCount = 0;

        // Binary search loop
        while (iterCount < MAX_COUNT_LEVERAGE_SEARCH_ITERATIONS) {
            uint mid = (lowScaled + highScaled) / 2;

            // Call the leverage calculation function
            uint resLeverageScaled = _fullLeverageCalculation(config, mid);

            // Check if we've converged
            uint delta = (resLeverageScaled > mid ? resLeverageScaled - mid : mid - resLeverageScaled);
            if (delta < toleranceScaled) {
                return mid;
            } else if (resLeverageScaled > mid) {
                lowScaled = mid;
            } else {
                highScaled = mid;
            }

            iterCount++;
        }

        return 0;
    }

    //endregion ------------------------------------- Withdraw

    //region ------------------------------------- Internal
    function getLeverageLendingAddresses(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $
    ) internal view returns (ILeverageLendingStrategy.LeverageLendingAddresses memory) {
        return ILeverageLendingStrategy.LeverageLendingAddresses({
            collateralAsset: $.collateralAsset,
            borrowAsset: $.borrowAsset,
            lendingVault: $.lendingVault,
            borrowingVault: $.borrowingVault
        });
    }

    function _getFlashLoanAddress(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address token
    ) internal view returns (address) {
        address universalAddress1 = $.universalAddress1;
        return token == $.borrowAsset
            ? universalAddress1 == address(0) ? $.flashLoanVault : universalAddress1
            : $.flashLoanVault;
    }

    //endregion ------------------------------------- Internal
}
