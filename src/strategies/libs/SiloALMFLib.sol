// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommonLib} from "../../core/libs/CommonLib.sol";
import {ConstantsLib} from "../../core/libs/ConstantsLib.sol";
import {IControllable} from "../../interfaces/IControllable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IFarmingStrategy} from "../../interfaces/IFarmingStrategy.sol";
import {ILeverageLendingStrategy} from "../../interfaces/ILeverageLendingStrategy.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IPriceReader} from "../../interfaces/IPriceReader.sol";
import {ISiloConfig} from "../../integrations/silo/ISiloConfig.sol";
import {ISiloLens} from "../../integrations/silo/ISiloLens.sol";
import {ISiloOracle} from "../../integrations/silo/ISiloOracle.sol";
import {ISilo} from "../../integrations/silo/ISilo.sol";
import {IMetaVault} from "../../interfaces/IMetaVault.sol";
import {IWrappedMetaVault} from "../../interfaces/IWrappedMetaVault.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {IVaultMainV3} from "../../integrations/balancerv3/IVaultMainV3.sol";
import {LeverageLendingLib} from "./LeverageLendingLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StrategyIdLib} from "./StrategyIdLib.sol";
import {StrategyLib} from "./StrategyLib.sol";

library SiloALMFLib {
    using SafeERC20 for IERC20;

    /// @dev 100_00 is 1.0 or 100%
    uint public constant INTERNAL_PRECISION = 100_00;

    /// @notice 1000 is 1%
    uint private constant PRICE_IMPACT_DENOMINATOR = 100_000;

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
    //endregion ------------------------------------- Data types

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

            // supply
            ISilo($.lendingVault).deposit(
                IERC20(collateralAsset).balanceOf(address(this)), address(this), ISilo.CollateralType.Collateral
            );

            // borrow
            ISilo($.borrowingVault).borrow(amount + feeAmount, address(this), address(this));

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.Withdraw) {
            uint tempCollateralAmount = $.tempCollateralAmount;
            uint swapPriceImpactTolerance0 = $.swapPriceImpactTolerance0;

            // repay debt
            ISilo($.borrowingVault).repay(amount, address(this));

            // withdraw
            {
                address lendingVault = $.lendingVault;
                uint collateralAmountTotal = totalCollateral(lendingVault);
                collateralAmountTotal -= collateralAmountTotal / 1000;

                ISilo(lendingVault).withdraw(
                    Math.min(tempCollateralAmount, collateralAmountTotal),
                    address(this),
                    address(this),
                    ISilo.CollateralType.Collateral
                );
            }

            // swap
            _swap(
                platform,
                collateralAsset,
                token,
                _estimateSwapAmount(
                    platform, amount + feeAmount, collateralAsset, token, swapPriceImpactTolerance0, tokenBalance0
                ),
                // Math.min(tempCollateralAmount, StrategyLib.balance(collateralAsset)),
                swapPriceImpactTolerance0
            );

            // explicit error for the case when _estimateSwapAmount gives incorrect amount
            require(
                _balanceWithoutRewards(token, tokenBalance0) >= amount + feeAmount, IControllable.InsufficientBalance()
            );

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // swap unnecessary borrow asset
            _swap(
                platform,
                token,
                collateralAsset,
                _balanceWithoutRewards(token, tokenBalance0),
                swapPriceImpactTolerance0
            );

            // reset temp vars
            $.tempCollateralAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.DecreaseLtv) {
            address lendingVault = $.lendingVault;

            // repay
            ISilo($.borrowingVault).repay(_balanceWithoutRewards(token, tokenBalance0), address(this));

            // withdraw amount
            ISilo(lendingVault).withdraw(
                $.tempCollateralAmount, address(this), address(this), ISilo.CollateralType.Collateral
            );

            // swap
            _swap(platform, collateralAsset, token, $.tempCollateralAmount, $.swapPriceImpactTolerance1);

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // repay remaining balance
            ISilo($.borrowingVault).repay(_balanceWithoutRewards(token, tokenBalance0), address(this));

            $.tempCollateralAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.IncreaseLtv) {
            uint tempCollateralAmount = $.tempCollateralAmount;

            // swap
            _swap(
                platform,
                token,
                collateralAsset,
                _balanceWithoutRewards(token, tokenBalance0) * $.increaseLtvParam1 / INTERNAL_PRECISION,
                $.swapPriceImpactTolerance1
            );

            // supply
            ISilo($.lendingVault).deposit(
                _getLimitedAmount(IERC20(collateralAsset).balanceOf(address(this)), tempCollateralAmount),
                address(this),
                ISilo.CollateralType.Collateral
            );

            // borrow
            ISilo($.borrowingVault).borrow(amount + feeAmount, address(this), address(this));

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // repay not used borrow
            uint tokenBalance = _balanceWithoutRewards(token, tokenBalance0);
            if (tokenBalance != 0) {
                ISilo($.borrowingVault).repay(tokenBalance, address(this));
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
        SiloALMFLib._receiveFlashLoan(platform, $, tokens[0], amounts[0], feeAmounts[0]);
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
        SiloALMFLib._receiveFlashLoan(platform, $, token, amount, 0); // assume that flash loan is free, fee is 0

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
        SiloALMFLib._receiveFlashLoan(platform, $, token, amount, isToken0 ? fee0 : fee1);
    }

    //endregion ------------------------------------- Flash loan

    //region ------------------------------------- View functions
    function getLtv(ILeverageLendingStrategy.LeverageLendingBaseStorage storage $) internal view returns (uint ltv) {
        return ISiloLens($.helper).getLtv($.lendingVault, address(this)) * INTERNAL_PRECISION / 1e18;
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
        CollateralDebtState memory debtState =
            _getDebtState(platform, $.lendingVault, $.collateralAsset, $.borrowAsset, $.borrowingVault);
        (ltv, maxLtv, leverage, collateralAmount, debtAmount, targetLeveragePercent) = _health(platform, $, debtState); // todo return
    }

    function rebalanceDebt(
        address platform,
        uint newLtv,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $
    ) external returns (uint resultLtv) {
        (uint ltv,,, uint collateralAmount, uint debtAmount,) = health(platform, $);

        ILeverageLendingStrategy.LeverageLendingAddresses memory v = ILeverageLendingStrategy.LeverageLendingAddresses({
            collateralAsset: $.collateralAsset,
            borrowAsset: $.borrowAsset,
            lendingVault: $.lendingVault,
            borrowingVault: $.borrowingVault
        });

        uint tvlPricedInCollateralAsset;
        uint priceCtoB;
        {
            uint priceBtoC;
            (priceCtoB, priceBtoC) = getPrices(v.lendingVault, v.borrowingVault);
            tvlPricedInCollateralAsset = StrategyLib.balance(v.collateralAsset) + calcTotal(v, priceBtoC);
        }

        // here is the math that works:
        // collateral_value - debt_value = real_TVL
        // debt_value * PRECISION / collateral_value = LTV
        // ---
        // collateral_value = real_TVL * PRECISION / (PRECISION - LTV)

        uint newCollateralValue = tvlPricedInCollateralAsset * INTERNAL_PRECISION / (INTERNAL_PRECISION - newLtv);
        uint newDebtAmount = newCollateralValue * newLtv * priceCtoB * (10 ** IERC20Metadata(v.borrowAsset).decimals())
            / INTERNAL_PRECISION / (10 ** IERC20Metadata(v.collateralAsset).decimals()) / 1e18; // priceCtoB has decimals 18

        uint debtDiff;
        if (newLtv < ltv) {
            // need decrease debt and collateral
            $.tempAction = ILeverageLendingStrategy.CurrentAction.DecreaseLtv;

            debtDiff = debtAmount - newDebtAmount;

            $.tempCollateralAmount = (collateralAmount - newCollateralValue) * $.decreaseLtvParam0 / INTERNAL_PRECISION;
        } else {
            // need increase debt and collateral
            $.tempAction = ILeverageLendingStrategy.CurrentAction.IncreaseLtv;

            debtDiff = (newDebtAmount - debtAmount) * $.increaseLtvParam0 / INTERNAL_PRECISION;
        }

        (address[] memory flashAssets, uint[] memory flashAmounts) = _getFlashLoanAmounts(debtDiff, v.borrowAsset);

        LeverageLendingLib.requestFlashLoan($, flashAssets, flashAmounts);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.None;
        resultLtv = SiloALMFLib.getLtv($);
    }

    function realTvl(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $
    ) public view returns (uint tvl, bool trusted) {
        CollateralDebtState memory debtState =
            _getDebtState(platform, $.lendingVault, $.collateralAsset, $.borrowAsset, $.borrowingVault);
        return _realTvl(debtState);
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
            uint priceC = ISiloOracle(collateralOracle).quote(
                10 ** IERC20Metadata(collateralConfig.token).decimals(), collateralConfig.token
            );
            uint priceB =
                ISiloOracle(borrowOracle).quote(10 ** IERC20Metadata(borrowConfig.token).decimals(), borrowConfig.token);

            priceCtoB = priceC * 1e18 / priceB; // todo
            priceBtoC = 1e18 * 1e18 / priceCtoB;
            // console.log("priceC, priceB, priceCtoB", priceC, priceB, priceCtoB);
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

    function calcTotal(
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        uint priceBtoC
    ) public view returns (uint total) {
        uint borrowedAmountPricedInCollateral = totalDebt(v.borrowingVault)
            * (10 ** IERC20Metadata(v.collateralAsset).decimals()) * priceBtoC
            / (10 ** IERC20Metadata(v.borrowAsset).decimals()) / 1e18; // priceBtoC has decimals 18

        total = totalCollateral(v.lendingVault) - borrowedAmountPricedInCollateral;
    }

    function totalCollateral(address lendingVault) public view returns (uint) {
        return IERC4626(lendingVault).convertToAssets(StrategyLib.balance(lendingVault));
    }

    function totalDebt(address borrowingVault) public view returns (uint) {
        return ISilo(borrowingVault).maxRepay(address(this));
    }

    function _realSharePrice(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address vault_
    ) public view returns (uint sharePrice, bool trusted) {
        uint __realTvl;
        (__realTvl, trusted) = realTvl(platform, $);
        uint totalSupply = IERC20(vault_).totalSupply();
        sharePrice = totalSupply == 0 ? 0 : __realTvl * 1e18 / totalSupply;
    }

    function getSpecificName(ILeverageLendingStrategy.LeverageLendingBaseStorage storage $)
        external
        view
        returns (string memory, bool)
    {
        address lendingVault = $.lendingVault;
        uint siloId = ISiloConfig(ISilo(lendingVault).config()).SILO_ID();
        string memory borrowAssetSymbol = IERC20Metadata($.borrowAsset).symbol();
        (,, uint targetLeverage) = getLtvData(lendingVault, $.targetLeveragePercent);
        return (
            string.concat(CommonLib.u2s(siloId), " ", borrowAssetSymbol, " ", _formatLeverageShort(targetLeverage)),
            false
        );
    }

    //endregion ------------------------------------- View functions

    //region ------------------------------------- Max deposit
    function maxDepositAssets(ILeverageLendingStrategy.LeverageLendingBaseStorage storage $)
        public
        view
        returns (uint[] memory amounts)
    {
        ILeverageLendingStrategy.LeverageLendingAddresses memory v = _getLeverageLendingAddresses($);

        // max deposit is limited by amount available to borrow from the borrow pool
        uint maxAmountInBorrowPool = ISilo(v.borrowingVault).getLiquidity();

        // take into account flash loan fee because it will be borrowed too
        uint maxBorrowAmount = maxAmountInBorrowPool * $.depositParam1 / INTERNAL_PRECISION;

        // max deposit is also limited by liquidity available in the flash loan vault
        uint flashLoanVaultBalance = IERC20(v.borrowAsset).balanceOf($.flashLoanVault);

        amounts = new uint[](1);
        amounts[0] = _getAmountToDepositFromBorrow($, v, Math.min(maxBorrowAmount, flashLoanVaultBalance));
    }
    //endregion ------------------------------------- Max deposit

    //region ------------------------------------- Deposit
    function depositAssets(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IStrategy.StrategyBaseStorage storage $base,
        uint amount,
        address asset
    ) external returns (uint value) {
        ILeverageLendingStrategy.LeverageLendingAddresses memory v = _getLeverageLendingAddresses($);

        (uint priceCtoB, uint priceBtoC) = getPrices(v.lendingVault, v.borrowingVault);
        uint valueWas = StrategyLib.balance(asset) + calcTotal(v, priceBtoC);

        _deposit($, v, amount, priceCtoB);

        (, priceBtoC) = getPrices(v.lendingVault, v.borrowingVault);
        uint valueNow = StrategyLib.balance(asset) + calcTotal(v, priceBtoC);

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

    function _deposit(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        uint amountToDeposit,
        uint priceCtoB
    ) internal {
        uint borrowAmount = _getDepositFlashAmount($, v, amountToDeposit, priceCtoB);
        (address[] memory flashAssets, uint[] memory flashAmounts) = _getFlashLoanAmounts(borrowAmount, v.borrowAsset);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.Deposit;
        LeverageLendingLib.requestFlashLoan($, flashAssets, flashAmounts);
    }

    function _getDepositFlashAmount(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        uint amountToDeposit,
        uint priceCtoB
    ) internal view returns (uint flashAmount) {
        (,, uint targetLeverage) = getLtvData(v.lendingVault, $.targetLeveragePercent);

        flashAmount = amountToDeposit * priceCtoB * (10 ** IERC20Metadata(v.borrowAsset).decimals())
            * (targetLeverage - INTERNAL_PRECISION) / INTERNAL_PRECISION / 1e18 // priceCtoB has decimals 1e18
            // depositParam0 is used to move result leverage to targetValue.
            // Otherwise result leverage is higher the target value because of swap losses
            * $.depositParam0 / INTERNAL_PRECISION / (10 ** IERC20Metadata(v.collateralAsset).decimals());
    }

    /// @notice Get what collateral amount should be deposited to borrow internally given {borrowAmount}
    /// @dev Flash fee is not taken into account here
    /// @param borrowAmount Amount received from {_getDepositFlashAmount}
    function _getAmountToDepositFromBorrow(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        uint borrowAmount
    ) internal view returns (uint amountToDeposit) {
        (,, uint targetLeverage) = getLtvData(v.lendingVault, $.targetLeveragePercent);
        (uint priceCtoB,) = getPrices(v.lendingVault, v.borrowingVault);

        amountToDeposit = borrowAmount * (10 ** IERC20Metadata(v.collateralAsset).decimals()) * 1e18 // priceCtoB has decimals 1e18
            * INTERNAL_PRECISION / (targetLeverage - INTERNAL_PRECISION) / priceCtoB
            / (10 ** IERC20Metadata(v.borrowAsset).decimals()) * INTERNAL_PRECISION / $.depositParam0;
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
        StateBeforeWithdraw memory state = _getStateBeforeWithdraw($, v);

        // ---------------------- withdraw from the lending vault - only if amount on the balance is not enough
        if (value > state.collateralBalanceStrategy) {
            // it's too dangerous to ask value - state.collateralBalanceStrategy
            // because current balance is used in multiple places inside receiveFlashLoan
            // so we ask to withdraw full required amount
            withdrawFromLendingVault(platform, $, v, state, value);
        }

        // ---------------------- Transfer required amount to the user, update base.total
        uint bal = StrategyLib.balance(v.collateralAsset);
        (uint priceCtoB, uint priceBtoC) = getPrices(v.lendingVault, v.borrowingVault);
        uint valueNow = bal + calcTotal(v, priceBtoC);

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
            _depositAfterWithdraw($, v, state.withdrawParam1, value, priceCtoB);
        }

        // ensure that result LTV doesn't exceed max
        _ensureLtvValid($, state.maxLtv);
    }

    function _depositAfterWithdraw(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        uint withdrawParam1,
        uint value,
        uint priceCtoB
    ) internal {
        uint balance = StrategyLib.balance(v.collateralAsset);

        // workaround dust problems and error LessThenThreshold
        uint maxAmountToWithdraw = withdrawParam1 * value / INTERNAL_PRECISION;
        if (balance > maxAmountToWithdraw * 100 / INTERNAL_PRECISION) {
            _deposit($, v, Math.min(maxAmountToWithdraw, balance), priceCtoB);
        }
    }

    function withdrawFromLendingVault(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        StateBeforeWithdraw memory state,
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
                ISilo(v.lendingVault).withdraw(
                    amountToWithdraw, address(this), address(this), ISilo.CollateralType.Collateral
                );
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
        uint collateralAmountToWithdraw =
            value * state.maxLeverage * state.withdrawParam0 / INTERNAL_PRECISION / INTERNAL_PRECISION;

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
        int leverageNew = int(
            _calculateNewLeverage(
                debtState.totalCollateralUsd,
                debtState.borrowAssetUsd,
                $.swapPriceImpactTolerance1, // use same MAX price impact as in the code processed IncreaseLtv
                value * debtState.collateralPrice / (10 ** IERC20Metadata(v.collateralAsset).decimals())
            )
        );

        if (leverageNew <= 0 || uint(leverageNew) > state.targetLeverage || uint(leverageNew) < leverage) {
            return false; // use default withdraw
        }

        uint priceCtoB;
        (priceCtoB,) = getPrices(v.lendingVault, v.borrowingVault);

        // --------- Calculate debt to add
        uint requiredCollateral = value * uint(leverageNew) / INTERNAL_PRECISION;
        uint debtDiff = requiredCollateral * priceCtoB // no multiplication on ltv here
            * (10 ** IERC20Metadata(v.borrowAsset).decimals()) / (10 ** IERC20Metadata(v.collateralAsset).decimals()) / 1e18; // priceCtoB has decimals 18

        (address[] memory flashAssets, uint[] memory flashAmounts) =
            _getFlashLoanAmounts(debtDiff * $.increaseLtvParam0 / INTERNAL_PRECISION, v.borrowAsset);

        // --------- Increase ltv: limit spending from both balances
        $.tempCollateralAmount = requiredCollateral;
        $.tempAction = ILeverageLendingStrategy.CurrentAction.IncreaseLtv;
        LeverageLendingLib.requestFlashLoan($, flashAssets, flashAmounts);

        // --------- Withdraw value from landing vault to the strategy balance
        ISilo(v.lendingVault).withdraw(value, address(this), address(this), ISilo.CollateralType.Collateral);

        return true;
    }

    /// @notice Calculate result leverage in assumption that we increase leverage and extract {value} of collateral
    /// @param xUsd Value of collateral in USD that we need to transfer to the user
    /// @param priceImpactTolerance Price impact tolerance. Denominator is {PRICE_IMPACT_DENOMINATOR}.
    /// @return leverageNew New leverage with 4 decimals or 0
    function _calculateNewLeverage(
        uint totalCollateralUsd,
        uint borrowAssetUsd,
        uint priceImpactTolerance,
        uint xUsd
    ) public pure returns (uint leverageNew) {
        // L_initial - current leverage
        // alpha = (1 - priceImpactTolerance), 18 decimals
        // X - collateral amount to withdraw
        // L_new = new leverage (it must be > current leverage)
        // D_inc - increment of the debt = L_new * X
        // C_add - new required collateral = D_inc * alpha
        // C_new = new collateral = C - X + C_add
        // D_new = new debt = D + D_inc
        // The math:
        //      L_new = C_new / (C_new - D_new)
        //      L_new^2 * [X * (alpha - 1)] + L_new * (C - X - D - X * alpha) + (-C + X) = 0
        // Solve square equation (alpha < 1)
        //      A = X * (alpha - 1), B = C - D - X - X * alpha, C_quad = -(C - X)
        //      L_new = [-B + sqrt(B^2 - 4*A*C_quad)] / 2 A
        // Solve linear equation (alpha = 1)
        //      L_new = (C - X) / (C - X - D - X)
        int alpha = int(1e18 * (PRICE_IMPACT_DENOMINATOR - priceImpactTolerance) / PRICE_IMPACT_DENOMINATOR);

        if (priceImpactTolerance == 0) {
            // solve linear equation
            int num = (int(totalCollateralUsd) - int(xUsd));
            int denum = (int(totalCollateralUsd) - int(xUsd) - int(borrowAssetUsd) - int(xUsd));
            return denum == 0 || (num / denum < 0) ? uint(0) : uint(num * int(INTERNAL_PRECISION) / denum);
        } else {
            int a = int(xUsd) * (alpha - 1e18) / 1e18;
            int b = int(totalCollateralUsd) - int(borrowAssetUsd) - int(xUsd) - int(xUsd) * int(alpha) / 1e18;
            int cQuad = -(int(totalCollateralUsd) - int(xUsd));

            int det2 = b * b - 4 * a * cQuad;
            if (det2 < 0) return 0;

            int ret = int(INTERNAL_PRECISION) * (-b + int(Math.sqrt(uint(det2)))) * 1e18 / (2 * a) / 1e18;
            return ret < 0 ? 0 : uint(ret);
        }
    }

    function _getStateBeforeWithdraw(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v
    ) public view returns (StateBeforeWithdraw memory state) {
        state.collateralBalanceStrategy = StrategyLib.balance(v.collateralAsset);
        (uint priceCtoB, uint priceBtoC) = getPrices(v.lendingVault, v.borrowingVault);
        state.valueWas = state.collateralBalanceStrategy + calcTotal(v, priceBtoC);
        state.ltv = getLtv($);
        state.priceCtoB = priceCtoB;
        (state.maxLtv, state.maxLeverage, state.targetLeverage) = getLtvData(v.lendingVault, $.targetLeveragePercent);
        state.withdrawParam0 = $.withdrawParam0;
        state.withdrawParam1 = $.withdrawParam1;
        state.withdrawParam2 = $.withdrawParam2;
        if (state.withdrawParam0 == 0) state.withdrawParam0 = 100_00;
        if (state.withdrawParam1 == 0) state.withdrawParam1 = 100_00;

        return state;
    }

    //endregion ------------------------------------- Withdraw

    //region ------------------------------------- Revenue and rewards
    function _claimRevenue(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IStrategy.StrategyBaseStorage storage $base,
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f
    ) external returns (uint[] memory __amounts, address[] memory __rewardAssets, uint[] memory __rewardAmounts) {
        __amounts = new uint[](1);
        ILeverageLendingStrategy.LeverageLendingAddresses memory v = SiloALMFLib._getLeverageLendingAddresses($);

        // ---------------------- Calculate amount earned through accrueInterest
        uint totalWas = $base.total;

        ISilo(v.lendingVault).accrueInterest();
        ISilo(v.borrowingVault).accrueInterest();

        (, uint priceBtoC) = getPrices(v.lendingVault, v.borrowingVault);
        uint totalNow = StrategyLib.balance(v.collateralAsset) + calcTotal(v, priceBtoC);
        if (totalNow > totalWas) {
            __amounts[0] = totalNow - totalWas;
        }

        // total will be updated later inside compound()

        // ---------------------- collect Merkl rewards
        __rewardAssets = $f._rewardAssets;
        uint rwLen = __rewardAssets.length;
        __rewardAmounts = new uint[](rwLen);
        for (uint i; i < rwLen; ++i) {
            // Reward asset can be equal to the borrow asset.
            // The borrow asset is never left on the balance, see _receiveFlashLoan().
            // So, any borrow asset on balance can be considered as a reward.
            __rewardAmounts[i] = StrategyLib.balance(__rewardAssets[i]);
        }
    }

    function _emitLeverageLendingHardWork(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        address vault_,
        uint realTvl_,
        uint duration,
        int earned
    ) internal {
        IPriceReader priceReader = _getPriceReader(platform);
        (uint collateralPrice,) = priceReader.getPrice(v.collateralAsset);
        int realEarned = earned * int(collateralPrice) / int(10 ** IERC20Metadata(v.collateralAsset).decimals());
        int realApr = StrategyLib.computeAprInt(realTvl_, realEarned, duration);
        (uint depositApr, uint borrowApr) = _getDepositAndBorrowAprs($.helper, v.lendingVault, v.borrowingVault);
        (uint sharePrice,) = _realSharePrice(platform, $, vault_);
        emit ILeverageLendingStrategy.LeverageLendingHardWork(
            realApr, earned, realTvl_, duration, sharePrice, depositApr, borrowApr
        );
    }

    function _getDepositAndBorrowAprs(
        address lens,
        address lendingVault,
        address debtVault
    ) internal view returns (uint depositApr, uint borrowApr) {
        depositApr = ISiloLens(lens).getDepositAPR(lendingVault) * ConstantsLib.DENOMINATOR / 1e18;
        borrowApr = ISiloLens(lens).getBorrowAPR(debtVault) * ConstantsLib.DENOMINATOR / 1e18;
    }

    function _compound(
        address platform,
        address vault_,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IStrategy.StrategyBaseStorage storage $base
    ) external {
        ILeverageLendingStrategy.LeverageLendingAddresses memory v = SiloALMFLib._getLeverageLendingAddresses($);

        // ---------------------- Calculate amount earned through rewards
        uint totalWas = $base.total;
        (uint priceCtoB, uint priceBtoC) = getPrices(v.lendingVault, v.borrowingVault);
        uint totalNow = StrategyLib.balance(v.collateralAsset) + calcTotal(v, priceBtoC);
        $base.total = totalNow;

        if (totalNow > totalWas) {
            uint[] memory _maxDepositAmounts = maxDepositAssets($);
            _deposit($, v, Math.min(_maxDepositAmounts[0], totalNow - totalWas), priceCtoB);
        }

        // ---------------------- Calculate apr and emit event
        (uint realTvl_,) = realTvl(platform, $);
        _emitLeverageLendingHardWork(
            platform, $, v, vault_, realTvl_, block.timestamp - $base.lastHardWork, int(totalNow) - int(totalWas)
        );

        (uint ltv,, uint leverage,,,) = health(platform, $);
        emit ILeverageLendingStrategy.LeverageLendingHealth(ltv, leverage);
    }

    //endregion ------------------------------------- Revenue and rewards

    //region ------------------------------------- Internal
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

    function _formatLeverageShort(uint amount) internal pure returns (string memory) {
        uint intAmount = amount / 100_00;
        uint decimalAmount = (amount - intAmount * 100_00) / 10_00;
        return string.concat("x", CommonLib.u2s(intAmount), ".", CommonLib.u2s(decimalAmount));
    }

    function _getDebtState(
        address platform,
        address lendingVault,
        address collateralAsset,
        address borrowAsset,
        address borrowingVault
    ) internal view returns (CollateralDebtState memory data) {
        bool collateralPriceTrusted;
        bool borrowAssetPriceTrusted;

        IPriceReader priceReader = _getPriceReader(platform);

        data.collateralAmount = totalCollateral(lendingVault);
        data.collateralBalance = StrategyLib.balance(collateralAsset);
        (data.collateralPrice, collateralPriceTrusted) = priceReader.getPrice(collateralAsset);
        data.totalCollateralUsd = (data.collateralAmount + data.collateralBalance) * data.collateralPrice
            / 10 ** IERC20Metadata(collateralAsset).decimals();

        data.debtAmount = totalDebt(borrowingVault);
        (data.borrowAssetPrice, borrowAssetPriceTrusted) = priceReader.getPrice(borrowAsset);
        data.borrowAssetUsd = data.debtAmount * data.borrowAssetPrice / 10 ** IERC20Metadata(borrowAsset).decimals();

        data.trusted = collateralPriceTrusted && borrowAssetPriceTrusted;

        return data;
    }

    /// @notice Estimate amount of collateral to swap to receive {amountToRepay} on balance
    /// @param priceImpactTolerance Price impact tolerance. Must include fees at least. Denominator is 100_000.
    function _estimateSwapAmount(
        address platform,
        uint amountToRepay,
        address collateralAsset,
        address token,
        uint priceImpactTolerance,
        uint rewardsBalance
    ) internal view returns (uint) {
        // We have collateral C = C1 + C2 where C1 is amount to withdraw, C2 is amount to swap to B (to repay)
        // We don't need to swap whole C, we can swap only C2 with same addon (i.e. 10%) for safety

        ISwapper swapper = ISwapper(IPlatform(platform).swapper());
        uint requiredAmount = amountToRepay - _balanceWithoutRewards(token, rewardsBalance);

        // we use higher (x2) price impact then required for safety
        uint minCollateralToSwap =
            swapper.getPrice(token, collateralAsset, requiredAmount * (100_000 + 2 * priceImpactTolerance) / 100_000); // priceImpactTolerance has its own denominator

        return Math.min(minCollateralToSwap, StrategyLib.balance(collateralAsset));
    }

    function _getPriceReader(address platform_) internal view returns (IPriceReader) {
        return IPriceReader(IPlatform(platform_).priceReader());
    }

    /// @notice ensure that result LTV doesn't exceed max
    function _ensureLtvValid(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        uint maxLtv
    ) internal view {
        uint ltv = getLtv($);
        require(ltv <= maxLtv, IControllable.IncorrectLtv(ltv));
    }

    function _getFlashLoanAmounts(
        uint borrowAmount,
        address borrowAsset
    ) internal pure returns (address[] memory flashAssets, uint[] memory flashAmounts) {
        flashAssets = new address[](1);
        flashAssets[0] = borrowAsset;
        flashAmounts = new uint[](1);
        flashAmounts[0] = borrowAmount;
    }

    function _getLeverageLendingAddresses(ILeverageLendingStrategy.LeverageLendingBaseStorage storage $)
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

    function _getLimitedAmount(uint amount, uint optionalLimit) internal pure returns (uint) {
        if (optionalLimit == 0) return amount;
        return Math.min(amount, optionalLimit);
    }

    function _balanceWithoutRewards(address borrowAsset, uint rewardsAmount) internal view returns (uint) {
        uint balance = StrategyLib.balance(borrowAsset);
        return balance > rewardsAmount ? balance - rewardsAmount : 0;
    }

    function _realTvl(CollateralDebtState memory debtState) internal pure returns (uint tvl, bool trusted) {
        tvl = debtState.totalCollateralUsd - debtState.borrowAssetUsd;
        trusted = debtState.trusted;
    }

    function _health(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        CollateralDebtState memory debtState_
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
        )
    {
        address lendingVault = $.lendingVault;
        address collateralAsset = $.collateralAsset;

        ltv = getLtv($);

        collateralAmount = StrategyLib.balance(collateralAsset) + totalCollateral(lendingVault);
        debtAmount = totalDebt($.borrowingVault);

        IPriceReader priceReader = _getPriceReader(platform);
        (uint __realTvl,) = _realTvl(debtState_);
        (uint collateralPrice,) = priceReader.getPrice(collateralAsset);
        uint collateralUsd = collateralAmount * collateralPrice / 10 ** IERC20Metadata(collateralAsset).decimals();

        leverage = __realTvl == 0 ? 0 : collateralUsd * INTERNAL_PRECISION / __realTvl;

        targetLeveragePercent = $.targetLeveragePercent;
        (maxLtv,,) = getLtvData(lendingVault, targetLeveragePercent);
    }
    //endregion ------------------------------------- Internal

    //region ------------------------------------- Transient prices cache
    function prepareWriteOp(address platform, address wrappedMetaVault) internal {
        // cache price of wrapped meta vault
        IPriceReader priceReader = SiloALMFLib._getPriceReader(platform);
        priceReader.preCalculatePriceTx(wrappedMetaVault);

        // cache price of all sub-vaults
        IMetaVault metaVault = _getMetaVault(wrappedMetaVault);
        metaVault.cachePrices(false);
        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1));
    }

    function unprepareWriteOp(address platform, address wrappedMetaVault) internal {
        IPriceReader priceReader = SiloALMFLib._getPriceReader(platform);
        priceReader.preCalculatePriceTx(address(0));

        IMetaVault metaVault = _getMetaVault(wrappedMetaVault);
        metaVault.cachePrices(true);
        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0));
    }

    function _getMetaVault(address wrappedMetaVault) internal view returns (IMetaVault) {
        // assume that collateral asset is always WrappedMetaVault, i.e. wmetaUSD
        return IMetaVault(IWrappedMetaVault(wrappedMetaVault).metaVault());
    }
    //region ------------------------------------- Transient prices cache
}
