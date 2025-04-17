// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {StrategyLib} from "./StrategyLib.sol";
import {ISilo} from "../../integrations/silo/ISilo.sol";
import {ISiloConfig} from "../../integrations/silo/ISiloConfig.sol";
import {ISiloOracle} from "../../integrations/silo/ISiloOracle.sol";
import {ISiloLens} from "../../integrations/silo/ISiloLens.sol";
import {ILeverageLendingStrategy} from "../../interfaces/ILeverageLendingStrategy.sol";
import {IPriceReader} from "../../interfaces/IPriceReader.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IControllable} from "../../interfaces/IControllable.sol";

library SiloLib {
    using SafeERC20 for IERC20;

    /// @dev 100_00 is 1.0 or 100%
    uint public constant INTERNAL_PRECISION = 100_00;

    function _executeSiloOperation(
        address lendingVault,
        uint amount,
        bool isDeposit,
        ISilo.CollateralType collateralType
    ) internal {
        if (isDeposit) {
            ISilo(lendingVault).deposit(amount, address(this), collateralType);
        } else {
            ISilo(lendingVault).withdraw(amount, address(this), address(this), collateralType);
        }
    }

    function _executeSwap(
        address platform,
        address tokenIn,
        address tokenOut,
        uint amount
    ) internal {
        StrategyLib.swap(platform, tokenIn, tokenOut, amount);
    }

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
            // Deposit flow
            _executeSiloOperation($.lendingVault, amount, true, ISilo.CollateralType.Collateral);
            ISilo($.borrowingVault).borrow($.tempBorrowAmount, address(this), address(this));
            _executeSwap(platform, $.borrowAsset, token, $.tempBorrowAmount);
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);
            _executeSiloOperation($.lendingVault, StrategyLib.balance(token), true, ISilo.CollateralType.Collateral);
            $.tempBorrowAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.Withdraw) {
            // Withdraw flow
            ISilo($.borrowingVault).repay(amount, address(this));
            uint collateralAmountTotal = totalCollateral($.lendingVault);
            collateralAmountTotal -= collateralAmountTotal / 1000;
            _executeSiloOperation(
                $.lendingVault,
                Math.min($.tempCollateralAmount, collateralAmountTotal),
                false,
                ISilo.CollateralType.Collateral
            );
            _executeSwap(platform, $.collateralAsset, token, Math.min($.tempCollateralAmount, StrategyLib.balance($.collateralAsset)));
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);
            _executeSwap(platform, token, $.collateralAsset, StrategyLib.balance(token));
            $.tempCollateralAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.DecreaseLtv) {
            // Decrease LTV flow
            _executeSwap(platform, token, $.borrowAsset, amount);
            ISilo($.borrowingVault).repay(StrategyLib.balance($.borrowAsset), address(this));
            uint toWithdraw = amount + feeAmount - StrategyLib.balance(token);
            _executeSiloOperation($.lendingVault, toWithdraw, false, ISilo.CollateralType.Collateral);
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.IncreaseLtv) {
            // Increase LTV flow
            _executeSiloOperation($.lendingVault, amount, true, ISilo.CollateralType.Collateral);
            ISilo($.borrowingVault).borrow($.tempBorrowAmount, address(this), address(this));
            _executeSwap(platform, $.borrowAsset, token, $.tempBorrowAmount);
            
            uint bal = StrategyLib.balance(token);
            uint remaining = bal < (amount + feeAmount) ? amount + feeAmount - bal : 0;
            if (remaining != 0) {
                _executeSiloOperation($.lendingVault, remaining, false, ISilo.CollateralType.Collateral);
            } else {
                uint toSupply = bal - (amount + feeAmount);
                _executeSiloOperation($.lendingVault, toSupply, true, ISilo.CollateralType.Collateral);
            }
            
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);
            $.tempBorrowAmount = 0;
        }

        (uint ltv,, uint leverage,,,) = health(platform, $);
        emit ILeverageLendingStrategy.LeverageLendingHealth(ltv, leverage);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.None;
    }

    struct HealthVars {
        address lendingVault;
        address collateralAsset;
        address borrowingVault;
        uint collateralPrice;
        uint collateralUsd;
        uint _realTvl;
    }

    function _calculatePrices(
        address platform,
        address collateralAsset,
        address borrowAsset
    ) internal view returns (uint collateralPrice, uint borrowPrice) {
        IPriceReader priceReader = IPriceReader(IPlatform(platform).priceReader());
        (collateralPrice,) = priceReader.getPrice(collateralAsset);
        (borrowPrice,) = priceReader.getPrice(borrowAsset);
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
        ltv = ISiloLens($.helper).getLtv($.lendingVault, address(this));
        ltv = ltv * INTERNAL_PRECISION / 1e18;

        collateralAmount = StrategyLib.balance($.collateralAsset) + totalCollateral($.lendingVault);
        debtAmount = totalDebt($.borrowingVault);

        (uint collateralPrice, uint borrowPrice) = _calculatePrices(platform, $.collateralAsset, $.borrowAsset);
        uint collateralUsd = collateralAmount * collateralPrice / 10 ** IERC20Metadata($.collateralAsset).decimals();
        uint debtUsd = debtAmount * borrowPrice / 10 ** IERC20Metadata($.borrowAsset).decimals();
        uint _realTvl = collateralUsd - debtUsd;

        leverage = collateralUsd * INTERNAL_PRECISION / _realTvl;
        targetLeveragePercent = $.targetLeveragePercent;

        (maxLtv,,) = getLtvData($.lendingVault, targetLeveragePercent);
        ltv = debtUsd * INTERNAL_PRECISION / collateralUsd;
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

    function getPrices(address platform, address lendVault, address debtVault) public view returns (uint priceCtoB, uint priceBtoC) {
        IPriceReader priceReader = IPriceReader(IPlatform(platform).priceReader());
        address collateralAsset = ISilo(lendVault).asset();
        address borrowAsset = ISilo(debtVault).asset();

        (uint collateralPrice,) = priceReader.getPrice(collateralAsset);
        (uint borrowPrice,) = priceReader.getPrice(borrowAsset);

        // Convert prices to 18 decimals in one step
        uint collateralDecimals = IERC20Metadata(collateralAsset).decimals();
        uint borrowDecimals = IERC20Metadata(borrowAsset).decimals();
        
        collateralPrice = collateralPrice * (10 ** (18 - collateralDecimals));
        borrowPrice = borrowPrice * (10 ** (18 - borrowDecimals));

        // Calculate price ratios
        priceCtoB = collateralPrice * 1e18 / borrowPrice;
        priceBtoC = borrowPrice * 1e18 / collateralPrice;
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

    function calcTotal(address platform, ILeverageLendingStrategy.LeverageLendingAddresses memory v) public view returns (uint) {
        uint collateralAmount = totalCollateral(v.lendingVault);
        uint debtAmount = totalDebt(v.borrowingVault);
        (, uint priceBtoC) = getPrices(platform, v.lendingVault, v.borrowingVault);
        return collateralAmount - debtAmount * priceBtoC / 1e18;
    }

    function totalCollateral(address lendingVault) public view returns (uint) {
        return IERC4626(lendingVault).convertToAssets(StrategyLib.balance(lendingVault));
    }

    function totalDebt(address borrowingVault) public view returns (uint) {
        return ISilo(borrowingVault).maxRepay(address(this));
    }
}
