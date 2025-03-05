// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

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

library SiloAdvancedLib {
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
        // token is borrow asset (USDC/WETH/wS)
        address collateralAsset = $.collateralAsset;
        address flashLoanVault = $.flashLoanVault;
        if (msg.sender != flashLoanVault) {
            revert IControllable.IncorrectMsgSender();
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.Deposit) {
            uint tempBorrowAmount = $.tempBorrowAmount;

            // swap
            StrategyLib.swap(platform, token, collateralAsset, amount, $.swapPriceImpactTolerance0);

            // supply
            ISilo($.lendingVault).deposit(
                IERC20(collateralAsset).balanceOf(address(this)), address(this), ISilo.CollateralType.Collateral
            );

            // borrow
            ISilo($.borrowingVault).borrow(tempBorrowAmount, address(this), address(this));

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // repay remaining balance
            ISilo($.borrowingVault).repay(StrategyLib.balance(token), address(this));

            // reset temp vars
            $.tempBorrowAmount = 0;
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
            StrategyLib.swap(
                platform,
                collateralAsset,
                token,
                Math.min(tempCollateralAmount, StrategyLib.balance(collateralAsset)),
                swapPriceImpactTolerance0
            );

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // swap unnecessary borrow asset
            StrategyLib.swap(platform, token, collateralAsset, StrategyLib.balance(token), swapPriceImpactTolerance0);

            // reset temp vars
            $.tempCollateralAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.DecreaseLtv) {
            address lendingVault = $.lendingVault;

            // repay
            ISilo($.borrowingVault).repay(StrategyLib.balance(token), address(this));

            // withdraw amount
            ISilo(lendingVault).withdraw(
                $.tempCollateralAmount, address(this), address(this), ISilo.CollateralType.Collateral
            );

            // swap
            StrategyLib.swap(platform, collateralAsset, token, $.tempCollateralAmount, $.swapPriceImpactTolerance1);

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // repay remaining balance
            ISilo($.borrowingVault).repay(StrategyLib.balance(token), address(this));

            $.tempCollateralAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.IncreaseLtv) {
            uint tempBorrowAmount = $.tempBorrowAmount;

            // swap
            StrategyLib.swap(
                platform,
                token,
                collateralAsset,
                IERC20(token).balanceOf(address(this)) * $.increaseLtvParam1 / INTERNAL_PRECISION,
                $.swapPriceImpactTolerance1
            );

            // supply
            ISilo($.lendingVault).deposit(
                IERC20(collateralAsset).balanceOf(address(this)), address(this), ISilo.CollateralType.Collateral
            );

            // borrow
            ISilo($.borrowingVault).borrow(tempBorrowAmount, address(this), address(this));

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // repay remaining balance
            ISilo($.borrowingVault).repay(StrategyLib.balance(token), address(this));

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
            priceCtoB = ISiloOracle(collateralOracle).quote(
                10 ** IERC20Metadata(collateralConfig.token).decimals(), collateralConfig.token
            );
            priceBtoC = 1e18 * 1e18 / priceCtoB;
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

    function calcTotal(ILeverageLendingStrategy.LeverageLendingAddresses memory v) external view returns (uint) {
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

    /*function _mintCollateralAsset(address token, address */

    /*tokenOut*/
    /*, uint amount) internal {
            if (token == TOKEN_USDC) {
            // mint scUSD
            IERC20(TOKEN_USDC).forceApprove(TOKEN_scUSD, amount);
            ITeller(TELLER_scUSD).deposit(TOKEN_USDC, amount, 0);
            // mint stkscUSD
            IERC20(TOKEN_scUSD).forceApprove(TOKEN_stkscUSD, amount);
            ITeller(TELLER_stkscUSD).deposit(TOKEN_scUSD, amount, 0);
            // mint wstkscUSD
            IERC20(TOKEN_stkscUSD).forceApprove(TOKEN_wstkscUSD, amount);
            IERC4626(TOKEN_wstkscUSD).deposit(amount, address(this));
            }
            }*/
}
