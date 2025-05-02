// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../../lib/forge-std/src/console.sol";
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
import {IVaultMainV3} from "../../integrations/balancerv3/IVaultMainV3.sol";
import {IUniswapV3PoolActions} from "../../integrations/uniswapv3/pool/IUniswapV3PoolActions.sol";
import {IUniswapV3PoolImmutables} from "../../integrations/uniswapv3/pool/IUniswapV3PoolImmutables.sol";

library SiloAdvancedLib {
    using SafeERC20 for IERC20;

    /// @dev 100_00 is 1.0 or 100%
    uint public constant INTERNAL_PRECISION = 100_00;

    /// @dev Variants of flashLoanKind
    uint public constant FLASH_LOAN_KIND_BALANCER_V2 = 0;
    uint public constant FLASH_LOAN_KIND_BALANCER_V3 = 1;
    uint public constant FLASH_LOAN_KIND_UNISWAP_V3 = 2;

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
        console.log("receiveFlashLoan");

        // token is borrow asset (USDC/WETH/wS)
        address collateralAsset = $.collateralAsset;
        address flashLoanVault = $.flashLoanVault;
        if (msg.sender != flashLoanVault) {
            revert IControllable.IncorrectMsgSender();
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.Deposit) {
            console.log('Do Deposit');

            console.log('Balance collateral', IERC20(collateralAsset).balanceOf(address(this)));
            console.log('Balance borrow', IERC20(token).balanceOf(address(this)));
            console.log("----- swap B=>C", amount);

            // swap
            _swap(platform, token, collateralAsset, amount, $.swapPriceImpactTolerance0);
            console.log('Balance collateral', IERC20(collateralAsset).balanceOf(address(this)));
            console.log('Balance borrow', IERC20(token).balanceOf(address(this)));

            // supply
            console.log("----- deposit C", IERC20(collateralAsset).balanceOf(address(this)));
            ISilo($.lendingVault).deposit(
                IERC20(collateralAsset).balanceOf(address(this)), address(this), ISilo.CollateralType.Collateral
            );

            // borrow
            console.log("----- borrow B", amount + feeAmount);
            ISilo($.borrowingVault).borrow(amount + feeAmount, address(this), address(this));
            console.log('Balance collateral', IERC20(collateralAsset).balanceOf(address(this)));
            console.log('Balance borrow', IERC20(token).balanceOf(address(this)));

            // pay flash loan
            console.log("----- transfer B", amount + feeAmount);
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);
            console.log('Balance collateral', IERC20(collateralAsset).balanceOf(address(this)));
            console.log('Balance borrow', IERC20(token).balanceOf(address(this)));
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.Withdraw) {
            console.log('Do Withdraw');
            uint tempCollateralAmount = $.tempCollateralAmount;
            uint swapPriceImpactTolerance0 = $.swapPriceImpactTolerance0;
            console.log('tempCollateralAmount', tempCollateralAmount);
            console.log('swapPriceImpactTolerance0', swapPriceImpactTolerance0);
            console.log('Balance collateral', IERC20(collateralAsset).balanceOf(address(this)));
            console.log('Balance borrow', IERC20(token).balanceOf(address(this)));

            // repay debt
            ISilo($.borrowingVault).repay(amount, address(this));
            console.log("----- repay B", amount);
            console.log('Balance collateral', IERC20(collateralAsset).balanceOf(address(this)));
            console.log('Balance borrow', IERC20(token).balanceOf(address(this)));

            // withdraw
            {
                address lendingVault = $.lendingVault;
                uint collateralAmountTotal = totalCollateral(lendingVault);
                console.log('collateralAmountTotal', collateralAmountTotal);
                collateralAmountTotal -= collateralAmountTotal / 1000;
                console.log('collateralAmountTotal', collateralAmountTotal);
                console.log("----- withdraw C", Math.min(tempCollateralAmount, collateralAmountTotal));
                ISilo(lendingVault).withdraw(
                    Math.min(tempCollateralAmount, collateralAmountTotal),
                    address(this),
                    address(this),
                    ISilo.CollateralType.Collateral
                );
            }
            console.log('Balance collateral', IERC20(collateralAsset).balanceOf(address(this)));
            console.log('Balance borrow', IERC20(token).balanceOf(address(this)));

            // swap
            StrategyLib.swap(
                platform,
                collateralAsset,
                token,
                _estimateCollateralAmountToRepay(
                    platform,
                    amount + feeAmount,
                    collateralAsset,
                    token,
                    tempCollateralAmount
                ),
                swapPriceImpactTolerance0
            );
            console.log('Balance collateral', IERC20(collateralAsset).balanceOf(address(this)));
            console.log('Balance borrow', IERC20(token).balanceOf(address(this)));

            console.log("----- pay flash loan B", amount + feeAmount);
            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);
            console.log('Balance collateral', IERC20(collateralAsset).balanceOf(address(this)));
            console.log('Balance borrow', IERC20(token).balanceOf(address(this)));

            console.log("swap unnecessary B", StrategyLib.balance(token));
            // swap unnecessary borrow asset
            StrategyLib.swap(platform, token, collateralAsset, StrategyLib.balance(token), swapPriceImpactTolerance0);
            console.log('Balance collateral', IERC20(collateralAsset).balanceOf(address(this)));
            console.log('Balance borrow', IERC20(token).balanceOf(address(this)));

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
        console.log("health");
        address lendingVault = $.lendingVault;
        address collateralAsset = $.collateralAsset;

        ltv = ISiloLens($.helper).getLtv(lendingVault, address(this));
        ltv = ltv * INTERNAL_PRECISION / 1e18;

        collateralAmount = StrategyLib.balance(collateralAsset) + totalCollateral(lendingVault);
        debtAmount = totalDebt($.borrowingVault);
        console.log("ltv", ltv);
        console.log("collateralAmount", collateralAmount);
        console.log("debtAmount", debtAmount);

        IPriceReader priceReader = IPriceReader(IPlatform(platform).priceReader());
        (uint _realTvl,) = realTvl(platform, $);
        (uint collateralPrice,) = priceReader.getPrice(collateralAsset);
        uint collateralUsd = collateralAmount * collateralPrice / 10 ** IERC20Metadata(collateralAsset).decimals();

        leverage = _realTvl == 0 ? 0 : collateralUsd * INTERNAL_PRECISION / _realTvl;

        console.log("_realTvl", _realTvl);
        console.log("collateralPrice", collateralPrice);
        console.log("collateralUsd", collateralUsd);
        console.log("leverage", leverage);

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

        uint tvlPricedInCollateralAsset = calcTotal(v);

        // here is the math that works:
        // collateral_value - debt_value = real_TVL
        // debt_value * PRECISION / collateral_value = LTV
        // ---
        // collateral_value = real_TVL * PRECISION / (PRECISION - LTV)

        uint newCollateralValue = tvlPricedInCollateralAsset * INTERNAL_PRECISION / (INTERNAL_PRECISION - newLtv);
        (uint priceCtoB,) = getPrices(v.lendingVault, v.borrowingVault);
        uint newDebtAmount = newCollateralValue * newLtv
            * priceCtoB
            * (10**IERC20Metadata(v.borrowAsset).decimals())
            / INTERNAL_PRECISION
            / (10**IERC20Metadata(v.collateralAsset).decimals())
            / 1e18; // priceCtoB has decimals 18

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

        SiloAdvancedLib.requestFlashLoan($, flashAssets, flashAmounts);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.None;
        (resultLtv,,,,,) = health(platform, $);
    }

    function realTvl(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $
    ) public view returns (uint tvl, bool trusted) {
        console.log("realTvl");
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
        console.log("collateralPrice", collateralPrice);
        console.log("borrowAssetPrice", borrowAssetPrice);
        console.log("collateralAmount", collateralAmount);
        console.log("collateralUsd", collateralUsd);
        console.log("borrowAssetUsd", borrowAssetUsd);
        console.log("tvl", tvl);
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
        console.log("maxLeverage", maxLeverage);
        targetLeverage = maxLeverage * targetLeveragePercent / INTERNAL_PRECISION;
        console.log("targetLeverage", targetLeverage);
    }

    function calcTotal(ILeverageLendingStrategy.LeverageLendingAddresses memory v) public view returns (uint) {
        console.log("calcTotal");
        (, uint priceBtoC) = getPrices(v.lendingVault, v.borrowingVault);
        console.log("priceBtoC", priceBtoC);
        console.log("borrow decimals", IERC20Metadata(v.borrowAsset).decimals());
        console.log("collateral decimals", IERC20Metadata(v.collateralAsset).decimals());
        uint borrowedAmountPricedInCollateral = totalDebt(v.borrowingVault)
            * (10**IERC20Metadata(v.collateralAsset).decimals())
            * priceBtoC
            / (10**IERC20Metadata(v.borrowAsset).decimals())
            / 1e18; // priceBtoC has decimals 18
        console.log("borrowedAmountPricedInCollateral", borrowedAmountPricedInCollateral);
        console.log("totalCollateral", totalCollateral(v.lendingVault));
        console.log("calcTotal", totalCollateral(v.lendingVault) - borrowedAmountPricedInCollateral);
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

    /// @dev Get flash loan and execute {receiveFlashLoan}
    function requestFlashLoan(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address[] memory flashAssets,
        uint256[] memory flashAmounts
    ) internal {
        address vault = $.flashLoanVault;
        uint flashLoanKind = $.flashLoanKind;

        if (flashLoanKind == FLASH_LOAN_KIND_BALANCER_V3) {
            console.log("requestFlashLoan.1");
            // fee amount are always 0,  flash loan in balancer v3 is free
            bytes memory data = abi.encodeWithSignature(
                "receiveFlashLoanV3(address,uint256,bytes)",
                flashAssets[0],
                flashAmounts[0],
                bytes("") // no user data
            );

            console.log("requestFlashLoan.2");
            IVaultMainV3(payable(vault)).unlock(data);

            console.log("requestFlashLoan.3");
        } else if (flashLoanKind == FLASH_LOAN_KIND_UNISWAP_V3) {
            // ensure that the vault has available amount
            require(IERC20(flashAssets[0]).balanceOf(address(vault)) >= flashAmounts[0], IControllable.InsufficientBalance());

            console.log("requestFlashLoan.4");
            bool isToken0 = IUniswapV3PoolImmutables(vault).token0() == flashAssets[0];
            IUniswapV3PoolActions(vault).flash(
                address(this),
                isToken0 ? flashAmounts[0] : 0,
                isToken0 ? 0 : flashAmounts[0],
                abi.encode(flashAssets[0], flashAmounts[0], isToken0)
            );
            console.log("requestFlashLoan.5");
        } else {
            console.log("requestFlashLoan.6");
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
        uint minCollateralToSwap = swapper.getPrice(token, collateralAsset, amountToRepay) * 110/100;
        console.log("amountToRepay", amountToRepay);
        console.log("minCollateralToSwap", minCollateralToSwap);
        console.log("collateralToSwap", Math.min(tempCollateralAmount, StrategyLib.balance(collateralAsset)));
        console.log("----- swap C=>B", Math.min(minCollateralToSwap, Math.min(tempCollateralAmount, StrategyLib.balance(collateralAsset))));
        return Math.min(minCollateralToSwap, Math.min(tempCollateralAmount, StrategyLib.balance(collateralAsset)));
    }
}
