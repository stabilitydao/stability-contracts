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
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {IWETH} from "../../integrations/weth/IWETH.sol";
import {IAnglesVault} from "../../integrations/angles/IAnglesVault.sol";
import {ITeller} from "../../interfaces/ITeller.sol";
import {IBVault} from "../../integrations/balancer/IBVault.sol";

library SiloAdvancedLib {
    using SafeERC20 for IERC20;

    /// @dev 100_00 is 1.0 or 100%
    uint public constant INTERNAL_PRECISION = 100_00;

    // mint wanS by wS
    address internal constant TOKEN_wS = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
    address internal constant ANGLES_VAULT = 0xe5203Be1643465b3c0De28fd2154843497Ef4269;
    address internal constant TOKEN_wanS = 0xfA85Fe5A8F5560e9039C04f2b0a90dE1415aBD70;

    // mint wstkscETH by wETH
    address internal constant TOKEN_wETH = 0x50c42dEAcD8Fc9773493ED674b675bE577f2634b;
    address internal constant TOKEN_scETH = 0x3bcE5CB273F0F148010BbEa2470e7b5df84C7812;
    address internal constant TOKEN_stkscETH = 0x455d5f11Fea33A8fa9D3e285930b478B6bF85265;
    address internal constant TELLER_scETH = 0x31A5A9F60Dc3d62fa5168352CaF0Ee05aA18f5B8;
    address internal constant TELLER_stkscETH = 0x49AcEbF8f0f79e1Ecb0fd47D684DAdec81cc6562;
    address internal constant TOKEN_wstkscETH = 0xE8a41c62BB4d5863C6eadC96792cFE90A1f37C47;

    // mint wstkscUSD by USDC
    address internal constant TOKEN_USDC = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address internal constant TOKEN_scUSD = 0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE;
    address internal constant TOKEN_stkscUSD = 0x4D85bA8c3918359c78Ed09581E5bc7578ba932ba;
    address internal constant TELLER_scUSD = 0x358CFACf00d0B4634849821BB3d1965b472c776a;
    address internal constant TELLER_stkscUSD = 0x5e39021Ae7D3f6267dc7995BB5Dd15669060DAe0;
    address internal constant TOKEN_wstkscUSD = 0x9fb76f7ce5FCeAA2C42887ff441D46095E494206;

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
            //console.log('deposit');

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
            //console.log('DecreaseLtv');
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
            //console.log('IncreaseLtv');

            // swap
            _swap(
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
            ISilo($.borrowingVault).borrow(amount + feeAmount, address(this), address(this));

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);
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
        (uint ltv,,, uint collateralAmount, uint debtAmount,) = health(platform, $);

        ILeverageLendingStrategy.LeverageLendingAddresses memory v = ILeverageLendingStrategy.LeverageLendingAddresses({
            collateralAsset: $.collateralAsset,
            borrowAsset: $.borrowAsset,
            lendingVault: $.lendingVault,
            borrowingVault: $.borrowingVault
        });

        uint tvlPricedInCollateralAsset = calcTotal(platform, v);

        // here is the math that works:
        // collateral_value - debt_value = real_TVL
        // debt_value * PRECISION / collateral_value = LTV
        // ---
        // collateral_value = real_TVL * PRECISION / (PRECISION - LTV)

        uint newCollateralValue = tvlPricedInCollateralAsset * INTERNAL_PRECISION / (INTERNAL_PRECISION - newLtv);
        (uint priceCtoB,) = getPrices(platform, v.lendingVault, v.borrowingVault);
        uint newDebtAmount = newCollateralValue * newLtv / INTERNAL_PRECISION * priceCtoB / 1e18;
        address[] memory flashAssets = new address[](1);
        flashAssets[0] = v.borrowAsset;
        uint[] memory flashAmounts = new uint[](1);

        if (newLtv < ltv) {
            // need decrease debt and collateral
            $.tempAction = ILeverageLendingStrategy.CurrentAction.DecreaseLtv;

            uint debtDiff = debtAmount - newDebtAmount;
            flashAmounts[0] = debtDiff;

            $.tempCollateralAmount = (collateralAmount - newCollateralValue) * $.decreaseLtvParam0 / INTERNAL_PRECISION;
        } else {
            // need increase debt and collateral
            $.tempAction = ILeverageLendingStrategy.CurrentAction.IncreaseLtv;

            uint debtDiff = newDebtAmount - debtAmount;
            flashAmounts[0] = debtDiff * $.increaseLtvParam0 / INTERNAL_PRECISION;
        }

        IBVault($.flashLoanVault).flashLoan(address(this), flashAssets, flashAmounts, "");

        $.tempAction = ILeverageLendingStrategy.CurrentAction.None;
        (resultLtv,,,,,) = health(platform, $);
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

    function getPrices(
        address platform,
        address lendVault,
        address debtVault
    ) public view returns (uint priceCtoB, uint priceBtoC) {
        ISiloConfig siloConfig = ISiloConfig(ISilo(lendVault).config());
        ISiloConfig.ConfigData memory collateralConfig = siloConfig.getConfig(lendVault);
        ISiloConfig.ConfigData memory borrowConfig = siloConfig.getConfig(debtVault);
        
        IPriceReader priceReader = IPriceReader(IPlatform(platform).priceReader());
        (uint collateralPrice,) = priceReader.getPrice(collateralConfig.token);
        (uint borrowPrice,) = priceReader.getPrice(borrowConfig.token);
        
        // Convert prices to 18 decimals if needed
        uint collateralDecimals = IERC20Metadata(collateralConfig.token).decimals();
        uint borrowDecimals = IERC20Metadata(borrowConfig.token).decimals();
        
        if (collateralDecimals < 18) {
            collateralPrice = collateralPrice * 10 ** (18 - collateralDecimals);
        } else if (collateralDecimals > 18) {
            collateralPrice = collateralPrice / 10 ** (collateralDecimals - 18);
        }
        
        if (borrowDecimals < 18) {
            borrowPrice = borrowPrice * 10 ** (18 - borrowDecimals);
        } else if (borrowDecimals > 18) {
            borrowPrice = borrowPrice / 10 ** (borrowDecimals - 18);
        }
        
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

    function calcTotal(
        address platform,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v
    ) public view returns (uint) {
        (, uint priceBtoC) = getPrices(platform, v.lendingVault, v.borrowingVault);
        uint borrowedAmountPricedInCollateral = totalDebt(v.borrowingVault) * priceBtoC / 1e18;
        return totalCollateral(v.lendingVault) - borrowedAmountPricedInCollateral;
    }

    function totalCollateral(address lendingVault) public view returns (uint) {
        return IERC4626(lendingVault).convertToAssets(StrategyLib.balance(lendingVault));
    }

    function totalDebt(address borrowingVault) public view returns (uint) {
        return ISilo(borrowingVault).maxRepay(address(this));
    }

    function _swap(
        address platform,
        address tokenIn,
        address tokenOut,
        uint amount,
        uint priceImpactTolerance
    ) internal {
        if (tokenIn == TOKEN_wS && tokenOut == TOKEN_wanS) {
            //console.log('ws to wans swap');
            // check price of swap without impact
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            uint outBySwap = swapper.getPrice(tokenIn, tokenOut, amount);
            //console.log('amount out by swap', outBySwap);

            uint outByMint = IERC4626(TOKEN_wanS).convertToShares(amount);
            //console.log('amount out by mint', outByMint);

            if (outByMint > outBySwap) {
                IWETH(tokenIn).withdraw(amount);
                IAnglesVault(ANGLES_VAULT).deposit{value: amount}();
                address ans = IERC4626(tokenOut).asset();
                IERC20(ans).forceApprove(tokenOut, amount);
                IERC4626(tokenOut).deposit(amount, address(this));
                //console.log('minted');
                return;
            }
        }

        if (tokenIn == TOKEN_USDC && tokenOut == TOKEN_wstkscUSD) {
            //console.log('USDC to wstkscUSDC swap');
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            uint outBySwap = swapper.getPrice(tokenIn, tokenOut, amount);
            //console.log('amount out by swap', outBySwap);
            uint outByMint = IERC4626(tokenOut).convertToShares(amount);
            //console.log('amount out by mint', outByMint);

            if (outByMint > outBySwap * 99_90 / 100_00) {
                // mint scUSD
                IERC20(TOKEN_USDC).forceApprove(TOKEN_scUSD, amount);
                ITeller(TELLER_scUSD).deposit(TOKEN_USDC, amount, 0);
                // mint stkscUSD
                IERC20(TOKEN_scUSD).forceApprove(TOKEN_stkscUSD, amount);
                ITeller(TELLER_stkscUSD).deposit(TOKEN_scUSD, amount, 0);
                // mint wstkscUSD
                IERC20(TOKEN_stkscUSD).forceApprove(TOKEN_wstkscUSD, amount);
                IERC4626(TOKEN_wstkscUSD).deposit(amount, address(this));
                //console.log('minted');
                return;
            }
        }

        if (tokenIn == TOKEN_wETH && tokenOut == TOKEN_wstkscETH) {
            //console.log('wETH to wstkscETH swap');
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            uint outBySwap = swapper.getPrice(tokenIn, tokenOut, amount);
            //console.log('amount out by swap', outBySwap);
            uint outByMint = IERC4626(tokenOut).convertToShares(amount);
            //console.log('amount out by mint', outByMint);

            if (outByMint > outBySwap * 99_50 / 100_00) {
                // mint scETH
                IERC20(TOKEN_wETH).forceApprove(TOKEN_scETH, amount);
                ITeller(TELLER_scETH).deposit(TOKEN_wETH, amount, 0);
                // mint stkscETH
                IERC20(TOKEN_scETH).forceApprove(TOKEN_stkscETH, amount);
                ITeller(TELLER_stkscETH).deposit(TOKEN_scETH, amount, 0);
                // mint wstkscETH
                IERC20(TOKEN_stkscETH).forceApprove(TOKEN_wstkscETH, amount);
                IERC4626(TOKEN_wstkscETH).deposit(amount, address(this));
                //console.log('minted');
                return;
            }
        }

        StrategyLib.swap(platform, tokenIn, tokenOut, amount, priceImpactTolerance);
    }
}
