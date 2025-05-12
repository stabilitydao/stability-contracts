// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../integrations/balancer/IBVault.sol";
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

library SiloLib {
    using SafeERC20 for IERC20;

    /// @dev 100_00 is 1.0 or 100%
    uint public constant INTERNAL_PRECISION = 100_00;

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
                ISilo(lendingVault).withdraw(
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
    }

    function realTvl(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $
    ) public view returns (uint tvl, bool trusted) {
        IPriceReader priceReader = IPriceReader(IPlatform(platform).priceReader());
        address lendingVault = $.lendingVault;
        address collateralAsset = $.collateralAsset;
        address borrowAsset = $.borrowAsset;
        uint collateralAmount = StrategyLib.balance(collateralAsset) + totalCollateral(lendingVault);
        (uint collateralPrice, bool CollateralPriceTrusted) = priceReader.getPrice(collateralAsset);
        uint collateralUsd = collateralAmount * collateralPrice / 10 ** IERC20Metadata(collateralAsset).decimals();
        uint borrowedAmount = totalDebt($.borrowingVault);
        (uint borrowAssetPrice, bool borrowAssetPriceTrusted) = priceReader.getPrice(borrowAsset);
        uint borrowAssetUsd = borrowedAmount * borrowAssetPrice / 10 ** IERC20Metadata(borrowAsset).decimals();
        tvl = collateralUsd - borrowAssetUsd;
        trusted = CollateralPriceTrusted && borrowAssetPriceTrusted;
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
        $.tempAction = ILeverageLendingStrategy.CurrentAction.Deposit;
        ILeverageLendingStrategy.LeverageLendingAddresses memory v = getLeverageLendingAddresses($);
        uint valueWas = StrategyLib.balance(_assets[0]) + calcTotal(v);

        (uint maxLtv,, uint targetLeverage) = getLtvData(v.lendingVault, $.targetLeveragePercent);

        uint[] memory flashAmounts = new uint[](1);
        flashAmounts[0] = amounts[0] * targetLeverage / INTERNAL_PRECISION;

        (uint priceCtoB,) = getPrices(v.lendingVault, v.borrowingVault);
        $.tempBorrowAmount = (flashAmounts[0] * maxLtv / 1e18) * priceCtoB / 1e18 - 2;

        IBVault($.flashLoanVault).flashLoan(address(this), _assets, flashAmounts, "");

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
    //endregion ------------------------------------- Deposit

    //region ------------------------------------- Withdraw

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
