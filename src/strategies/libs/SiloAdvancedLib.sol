// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Test.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {IAnglesVault} from "../../integrations/angles/IAnglesVault.sol";
import {IBVault} from "../../integrations/balancer/IBVault.sol";
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
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {ITeller} from "../../interfaces/ITeller.sol";
import {IUniswapV3PoolActions} from "../../integrations/uniswapv3/pool/IUniswapV3PoolActions.sol";
import {IUniswapV3PoolImmutables} from "../../integrations/uniswapv3/pool/IUniswapV3PoolImmutables.sol";
import {IVaultMainV3} from "../../integrations/balancerv3/IVaultMainV3.sol";
import {IWETH} from "../../integrations/weth/IWETH.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StrategyLib} from "./StrategyLib.sol";

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
        // token is borrow asset (USDC/WETH/wS)
        address collateralAsset = $.collateralAsset;
        address flashLoanVault = $.flashLoanVault;
        if (msg.sender != flashLoanVault) {
            revert IControllable.IncorrectMsgSender();
        }

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
            console.log("receiveFlashLoan.1");
            uint tempCollateralAmount = $.tempCollateralAmount;
            uint swapPriceImpactTolerance0 = $.swapPriceImpactTolerance0;

            console.log('Do Withdraw');
            console.log('tempCollateralAmount', tempCollateralAmount);
            console.log('swapPriceImpactTolerance0', swapPriceImpactTolerance0);
            console.log('Balance collateral', IERC20(collateralAsset).balanceOf(address(this)));
            console.log('Balance borrow', IERC20(token).balanceOf(address(this)));
            console.log("----- repay B", amount);

            // repay debt
            ISilo($.borrowingVault).repay(amount, address(this));
            console.log('Balance collateral', IERC20(collateralAsset).balanceOf(address(this)));
            console.log('Balance borrow', IERC20(token).balanceOf(address(this)));

            // withdraw
            {
                console.log("receiveFlashLoan.3");
                address lendingVault = $.lendingVault;
                uint collateralAmountTotal = totalCollateral(lendingVault);
                console.log('collateralAmountTotal', collateralAmountTotal);
                collateralAmountTotal -= collateralAmountTotal / 1000;
                console.log("----- withdraw C", Math.min(tempCollateralAmount, collateralAmountTotal));
                ISilo(lendingVault).withdraw(
                    Math.min(tempCollateralAmount, collateralAmountTotal),
                    address(this),
                    address(this),
                    ISilo.CollateralType.Collateral
                );
                console.log('Balance collateral', IERC20(collateralAsset).balanceOf(address(this)));
                console.log('Balance borrow', IERC20(token).balanceOf(address(this)));
                // console.log('swap C=>B', Math.min(tempCollateralAmount, StrategyLib.balance(collateralAsset)));
                console.log('swap C=>B', _estimateCollateralAmountToRepay(platform, amount + feeAmount, collateralAsset, token, tempCollateralAmount));

            }

            // swap
            console.log("receiveFlashLoan.4");
            {
//                uint balanceBorrow = IERC20(token).balanceOf(address(this));
//                if (balanceBorrow < amount + feeAmount) {
                    StrategyLib.swap(
                        platform,
                        collateralAsset,
                        token,
                        //TODO _estimateCollateralAmountToRepay(platform, amount + feeAmount, collateralAsset, token, tempCollateralAmount),
                         Math.min(tempCollateralAmount, StrategyLib.balance(collateralAsset)),
                        swapPriceImpactTolerance0
                    );
//                }
            }
            console.log('Balance collateral', IERC20(collateralAsset).balanceOf(address(this)));
            console.log('Balance borrow', IERC20(token).balanceOf(address(this)));
            console.log("----- pay flash loan B", amount + feeAmount);
            console.log("flashLoanAmount", amount + feeAmount);
            console.log("feeAmount", feeAmount);

            // pay flash loan
            console.log("receiveFlashLoan.5", amount + feeAmount, StrategyLib.balance(token));
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);
            console.log('Balance collateral', IERC20(collateralAsset).balanceOf(address(this)));
            console.log('Balance borrow', IERC20(token).balanceOf(address(this)));
            console.log("swap unnecessary B", StrategyLib.balance(token));

            // swap unnecessary borrow asset
            console.log("receiveFlashLoan.6");
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
            uint tempCollateralAmount = $.tempCollateralAmount;

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
                _getLimitedAmount(IERC20(collateralAsset).balanceOf(address(this)), tempCollateralAmount),
                address(this),
                ISilo.CollateralType.Collateral
            );

            // borrow
            ISilo($.borrowingVault).borrow(amount + feeAmount, address(this), address(this));

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // repay not used borrow
            uint tokenBalance = IERC20(token).balanceOf(address(this));
            if (tokenBalance != 0) {
                ISilo($.borrowingVault).repay(tokenBalance, address(this));
            }

            // reset temp vars
            if (tempCollateralAmount != 0) {
                $.tempCollateralAmount = 0;
            }
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

        leverage = _realTvl == 0 ? 0 : collateralUsd * INTERNAL_PRECISION / _realTvl;

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

        uint tvlPricedInCollateralAsset = StrategyLib.balance(v.collateralAsset) + calcTotal(v);

        // here is the math that works:
        // collateral_value - debt_value = real_TVL
        // debt_value * PRECISION / collateral_value = LTV
        // ---
        // collateral_value = real_TVL * PRECISION / (PRECISION - LTV)

        uint newCollateralValue = tvlPricedInCollateralAsset * INTERNAL_PRECISION / (INTERNAL_PRECISION - newLtv);
        (uint priceCtoB,) = getPrices(v.lendingVault, v.borrowingVault);
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

        SiloAdvancedLib.requestFlashLoan($, flashAssets, flashAmounts);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.None;
        (resultLtv,,,,,) = health(platform, $);
    }

    function realTvl(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $
    ) public view returns (uint tvl, bool trusted) {
        SiloAdvancedLib.CollateralDebtState memory debtState =
            getDebtState(platform, $.lendingVault, $.collateralAsset, $.borrowAsset, $.borrowingVault);
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
        data.totalCollateralUsd = (data.collateralAmount + data.collateralBalance) * data.collateralPrice
            / 10 ** IERC20Metadata(collateralAsset).decimals();

        data.debtAmount = totalDebt(borrowingVault);
        (data.borrowAssetPrice, borrowAssetPriceTrusted) = priceReader.getPrice(borrowAsset);
        data.borrowAssetUsd = data.debtAmount * data.borrowAssetPrice / 10 ** IERC20Metadata(borrowAsset).decimals();

        data.trusted = collateralPriceTrusted && borrowAssetPriceTrusted;

        console.log("collateralPrice", data.collateralPrice);
        console.log("borrowAssetPrice", data.borrowAssetPrice);
        console.log("balance collateral", data.collateralBalance);
        console.log("collateralAmount", data.collateralAmount);
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
        console.log("maxLtv", maxLtv);
        console.log("maxLeverage", maxLeverage);
        console.log("targetLeverage", targetLeverage);
    }

    function calcTotal(ILeverageLendingStrategy.LeverageLendingAddresses memory v) public view returns (uint) {
        (, uint priceBtoC) = getPrices(v.lendingVault, v.borrowingVault);
        uint borrowedAmountPricedInCollateral = totalDebt(v.borrowingVault)
            * (10 ** IERC20Metadata(v.collateralAsset).decimals()) * priceBtoC
            / (10 ** IERC20Metadata(v.borrowAsset).decimals()) / 1e18; // priceBtoC has decimals 18

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
        console.log("Swapper", IPlatform(platform).swapper());
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

    /// @dev Get flash loan and execute {receiveFlashLoan}
    function requestFlashLoan(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address[] memory flashAssets,
        uint[] memory flashAmounts
    ) internal {
        console.log("requestFlashLoan", flashAmounts[0]);
        address vault = $.flashLoanVault;
        ILeverageLendingStrategy.FlashLoanKind flashLoanKind = ILeverageLendingStrategy.FlashLoanKind($.flashLoanKind);

        if (flashLoanKind == ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1) {
            // fee amount are always 0,  flash loan in balancer v3 is free
            bytes memory data = abi.encodeWithSignature(
                "receiveFlashLoanV3(address,uint256,bytes)",
                flashAssets[0],
                flashAmounts[0],
                bytes("") // no user data
            );

            IVaultMainV3(payable(vault)).unlock(data);
        } else if (
            flashLoanKind == ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2
            // assume here that Algebra uses exactly same API as UniswapV3
            || flashLoanKind == ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3
        ) {
            // ensure that the pool has available amount
            require(
                IERC20(flashAssets[0]).balanceOf(address(vault)) >= flashAmounts[0], IControllable.InsufficientBalance()
            );

            bool isToken0 = IUniswapV3PoolImmutables(vault).token0() == flashAssets[0];
            IUniswapV3PoolActions(vault).flash(
                address(this),
                isToken0 ? flashAmounts[0] : 0,
                isToken0 ? 0 : flashAmounts[0],
                abi.encode(flashAssets[0], flashAmounts[0], isToken0)
            );
        } else {
            // FLASH_LOAN_KIND_BALANCER_V2: paid
            IBVault(vault).flashLoan(address(this), flashAssets, flashAmounts, "");
        }
    }

    function _estimateCollateralAmountToRepay(
        address platform,
        uint amountToRepay,
        address collateralAsset,
        address token,
        uint tempCollateralAmount
    ) internal view returns (uint) {
        // We have collateral C = C1 + C2 where C1 is amount to withdraw, C2 is amount to swap to B (to repay)
        // We don't need to swap whole C, we can swap only C2 with same addon (i.e. 10%) for safety

        ISwapper swapper = ISwapper(IPlatform(platform).swapper());

        // 10% for price impact and slippage
        uint minCollateralToSwap = swapper.getPrice(token, collateralAsset, amountToRepay) * 110 / 100;
        console.log("minCollateralToSwap", minCollateralToSwap);
        console.log("tempCollateralAmount", tempCollateralAmount);
        console.log("balance",  StrategyLib.balance(collateralAsset));

        return Math.min(minCollateralToSwap, Math.min(tempCollateralAmount, StrategyLib.balance(collateralAsset)));
    }

    //region ------------------------------------- Deposit
    function depositAssets(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IStrategy.StrategyBaseStorage storage $base,
        uint amount,
        address asset
    ) external returns (uint value) {
        ILeverageLendingStrategy.LeverageLendingAddresses memory v = SiloAdvancedLib.getLeverageLendingAddresses($);

        uint valueWas = StrategyLib.balance(asset) + calcTotal(v);
        _deposit($, v, amount);
        uint valueNow = StrategyLib.balance(asset) + calcTotal(v);

        if (valueNow > valueWas) {
            value = amount + (valueNow - valueWas);
        } else {
            value = amount - (valueWas - valueNow);
        }

        $base.total += value;
    }

    function _deposit(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        uint amountToDeposit
    ) internal {
        (address[] memory flashAssets, uint[] memory flashAmounts) =
            _getFlashLoanAmounts(_getDepositFlashAmount($, v, amountToDeposit), v.borrowAsset);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.Deposit;
        requestFlashLoan($, flashAssets, flashAmounts);
    }

    function _getDepositFlashAmount(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        uint amountToDeposit
    ) internal view returns (uint flashAmount) {
        (,, uint targetLeverage) = getLtvData(v.lendingVault, $.targetLeveragePercent);

        (uint priceCtoB,) = getPrices(v.lendingVault, v.borrowingVault);

        return amountToDeposit * priceCtoB * (10 ** IERC20Metadata(v.borrowAsset).decimals())
            * (targetLeverage - INTERNAL_PRECISION) / INTERNAL_PRECISION / 1e18 // priceCtoB has decimals 1e18
            / (10 ** IERC20Metadata(v.collateralAsset).decimals());
        // not sure that its right way, but its working
        // flashAmounts[0] = flashAmounts[0] * $.depositParam0 / INTERNAL_PRECISION;
    }

    //endregion ------------------------------------- Deposit

    //region ------------------------------------- Withdraw
    /// @dev The strategy uses withdrawParam0 and withdrawParam1
    ///     - withdrawParam0 is used to correct auto calculated flashAmount
    ///     - withdrawParam1 is used to correct value asked by the user, to be able to withdraw more than user wants
    ///                      Rest amount is deposited back (such trick allows to fix reduced leverage/ltv)
    function withdrawAssets(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IStrategy.StrategyBaseStorage storage $base,
        uint value,
        address receiver
    ) external returns (uint[] memory amountsOut) {
        console.log("withdrawAssets.1");
        ILeverageLendingStrategy.LeverageLendingAddresses memory v = getLeverageLendingAddresses($);
        SiloAdvancedLib.StateBeforeWithdraw memory state = _getStateBeforeWithdraw(platform, $, v);

        // ---------------------- withdraw from the lending vault - only if amount on the balance is not enough
        if (value > state.collateralBalanceStrategy) {
            console.log("withdrawAssets.2");
            // it's too dangerous to ask value - state.collateralBalanceStrategy
            // because current balance is used in multiple places inside receiveFlashLoan
            // so we ask to withdraw full required amount
            withdrawFromLendingVault(platform, $, v, state, value);
        }

        // ---------------------- Transfer required amount to the user, update base.total
        uint bal = StrategyLib.balance(v.collateralAsset);
        uint valueNow = bal + calcTotal(v);
        console.log("withdrawAssets.3");

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
            console.log("withdrawAssets.4");
            uint balance = StrategyLib.balance(v.collateralAsset);
            if (balance != 0) {
                SiloAdvancedLib._deposit($, v, Math.min(state.withdrawParam1 * value / INTERNAL_PRECISION, balance));
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
        console.log("withdrawFromLendingVault.1");
        (,, uint leverage,,,) = health(platform, $);

        SiloAdvancedLib.CollateralDebtState memory debtState =
            getDebtState(platform, v.lendingVault, v.collateralAsset, v.borrowAsset, v.borrowingVault);

        if (0 == debtState.debtAmount) {
            console.log("withdrawFromLendingVault.2");
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
            console.log("withdrawFromLendingVault.3");
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
                console.log("withdrawFromLendingVault.4");
                _withdrawReduceLeverage($, v, state, valueToWithdraw);
                console.log("withdrawFromLendingVault.5");
            }
        }

        // ensure that result LTV doesn't exceed max
        (uint ltv,,,,,) = health(platform, $);
        require(ltv <= state.maxLtv, IControllable.IncorrectLtv(ltv));
    }

    function _withdrawReduceLeverage(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        StateBeforeWithdraw memory state,
        uint value
    ) internal {
        console.log("!!!_withdrawReduceLeverage.1");
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

        console.log("_withdrawReduceLeverage.value", value);
        console.log("_withdrawReduceLeverage.collateralAmountToWithdraw", collateralAmountToWithdraw);
        console.log("_withdrawReduceLeverage.flashAmounts[0]", flashAmounts[0]);
        console.log("_withdrawReduceLeverage.withdrawParam0", state.withdrawParam0);
        console.log("_withdrawReduceLeverage.priceCtoB", state.priceCtoB);

        $.tempCollateralAmount = collateralAmountToWithdraw;
        $.tempAction = ILeverageLendingStrategy.CurrentAction.Withdraw;
        console.log("_withdrawReduceLeverage.2", flashAmounts[0]);
        SiloAdvancedLib.requestFlashLoan($, flashAssets, flashAmounts);
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

        (address[] memory flashAssets, uint[] memory flashAmounts) =
            _getFlashLoanAmounts(debtDiff * $.increaseLtvParam0 / INTERNAL_PRECISION, v.borrowAsset);

        // --------- Increase ltv: limit spending from both balances
        $.tempCollateralAmount = value * uint(leverageNew);
        $.tempAction = ILeverageLendingStrategy.CurrentAction.IncreaseLtv;
        SiloAdvancedLib.requestFlashLoan($, flashAssets, flashAmounts);

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
    function _getFlashLoanAmounts(
        uint borrowAmount,
        address borrowAsset
    ) internal pure returns (address[] memory flashAssets, uint[] memory flashAmounts) {
        flashAssets = new address[](1);
        flashAssets[0] = borrowAsset;
        flashAmounts = new uint[](1);
        flashAmounts[0] = borrowAmount;
    }

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

    function _getLimitedAmount(uint amount, uint optionalLimit) internal pure returns (uint) {
        if (optionalLimit == 0) return amount;
        return Math.min(amount, optionalLimit);
    }
    //endregion ------------------------------------- Internal
}
