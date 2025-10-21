// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMainstreetMinter} from "../../integrations/mainstreet/IMainstreetMinter.sol";
import {IAnglesVault} from "../../integrations/angles/IAnglesVault.sol";
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
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {ITeller} from "../../interfaces/ITeller.sol";
import {IWETH} from "../../integrations/weth/IWETH.sol";
import {LeverageLendingLib} from "./LeverageLendingLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StrategyLib} from "./StrategyLib.sol";

library SiloAdvancedLib {
    using SafeERC20 for IERC20;

    /// @notice Value of depositParams1 - it means that the collateral asset is PT and the PT market it expired
    uint public constant COLLATERAL_IS_PT_EXPIRED_MARKET = 1;

    /// @dev 100_00 is 1.0 or 100%
    uint public constant INTERNAL_PRECISION = 100_00;

    /// @notice 1000 is 1%
    uint private constant PRICE_IMPACT_DENOMINATOR = 100_000;

    // mint wanS by wS
    address internal constant TOKEN_WS = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
    address internal constant ANGLES_VAULT = 0xe5203Be1643465b3c0De28fd2154843497Ef4269;
    address internal constant TOKEN_WANS = 0xfA85Fe5A8F5560e9039C04f2b0a90dE1415aBD70;

    // mint wstkscETH by wETH
    address internal constant TOKEN_WETH = 0x50c42dEAcD8Fc9773493ED674b675bE577f2634b;
    address internal constant TOKEN_SCETH = 0x3bcE5CB273F0F148010BbEa2470e7b5df84C7812;
    address internal constant TOKEN_STKSCETH = 0x455d5f11Fea33A8fa9D3e285930b478B6bF85265;
    address internal constant TELLER_SCETH = 0x31A5A9F60Dc3d62fa5168352CaF0Ee05aA18f5B8;
    address internal constant TELLER_STKSCETH = 0x49AcEbF8f0f79e1Ecb0fd47D684DAdec81cc6562;
    address internal constant TOKEN_WSTKSCETH = 0xE8a41c62BB4d5863C6eadC96792cFE90A1f37C47;

    // mint wstkscUSD by USDC
    address internal constant TOKEN_USDC = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address internal constant TOKEN_SCUSD = 0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE;
    address internal constant TOKEN_STKSCUSD = 0x4D85bA8c3918359c78Ed09581E5bc7578ba932ba;
    address internal constant TELLER_SCUSD = 0x358CFACf00d0B4634849821BB3d1965b472c776a;
    address internal constant TELLER_STKSCUSD = 0x5e39021Ae7D3f6267dc7995BB5Dd15669060DAe0;
    address internal constant TOKEN_WSTKSCUSD = 0x9fb76f7ce5FCeAA2C42887ff441D46095E494206;

    // mint msUSD by USDC, stake to smsUSD
    address internal constant TOKEN_SMSUSD = 0xc7990369DA608C2F4903715E3bD22f2970536C29;
    address internal constant TOKEN_MSUSD = 0xE5Fb2Ed6832deF99ddE57C0b9d9A56537C89121D;
    address internal constant MSUSD_MINTER = 0xb1E423c251E989bd4e49228eF55aC4747D63F54D;

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

    struct ReceiveFlashLoanLocal {
        bool ptExpiredMode;
        address collateralAsset;
        address flashLoanVault;
    }

    //endregion ------------------------------------- Data types

    function receiveFlashLoan(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address token,
        uint amount,
        uint feeAmount
    ) external {
        //slither-disable-next-line uninitialized-local
        ReceiveFlashLoanLocal memory v;

        // token is borrow asset (USDC/WETH/wS)
        v.ptExpiredMode = _isPtExpiredMode($);
        v.collateralAsset = $.collateralAsset;
        v.flashLoanVault = $.flashLoanVault;

        if (msg.sender != v.flashLoanVault) {
            revert IControllable.IncorrectMsgSender();
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.Deposit) {
            // swap
            _swap(platform, token, v.collateralAsset, amount, $.swapPriceImpactTolerance0);

            // supply
            ISilo($.lendingVault)
                .deposit(
                    IERC20(v.collateralAsset).balanceOf(address(this)), address(this), ISilo.CollateralType.Collateral
                );

            // borrow
            ISilo($.borrowingVault).borrow(amount + feeAmount, address(this), address(this));

            // pay flash loan
            IERC20(token).safeTransfer(v.flashLoanVault, amount + feeAmount);
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

                ISilo(lendingVault)
                    .withdraw(
                        Math.min(tempCollateralAmount, collateralAmountTotal),
                        address(this),
                        address(this),
                        ISilo.CollateralType.Collateral
                    );
            }

            _swapForWithdraw(platform, v, token, amount + feeAmount, swapPriceImpactTolerance0);

            // explicit error for the case when _estimateSwapAmount gives incorrect amount
            require(IERC20(token).balanceOf(address(this)) >= amount + feeAmount, IControllable.InsufficientBalance());

            // pay flash loan
            IERC20(token).safeTransfer(v.flashLoanVault, amount + feeAmount);

            // swap unnecessary borrow asset
            if (!v.ptExpiredMode && StrategyLib.balance(token) != 0) {
                StrategyLib.swap(
                    platform, token, v.collateralAsset, StrategyLib.balance(token), swapPriceImpactTolerance0
                );
            }

            // reset temp vars
            $.tempCollateralAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.DecreaseLtv) {
            address lendingVault = $.lendingVault;

            // repay
            ISilo($.borrowingVault).repay(StrategyLib.balance(token), address(this));

            // withdraw amount
            ISilo(lendingVault)
                .withdraw($.tempCollateralAmount, address(this), address(this), ISilo.CollateralType.Collateral);

            // swap
            StrategyLib.swap(platform, v.collateralAsset, token, $.tempCollateralAmount, $.swapPriceImpactTolerance1);

            // pay flash loan
            IERC20(token).safeTransfer(v.flashLoanVault, amount + feeAmount);

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
                v.collateralAsset,
                IERC20(token).balanceOf(address(this)) * $.increaseLtvParam1 / INTERNAL_PRECISION,
                $.swapPriceImpactTolerance1
            );

            // supply
            ISilo($.lendingVault)
                .deposit(
                    _getLimitedAmount(IERC20(v.collateralAsset).balanceOf(address(this)), tempCollateralAmount),
                    address(this),
                    ISilo.CollateralType.Collateral
                );

            // borrow
            ISilo($.borrowingVault).borrow(amount + feeAmount, address(this), address(this));

            // pay flash loan
            IERC20(token).safeTransfer(v.flashLoanVault, amount + feeAmount);

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

    function _swapForWithdraw(
        address platform,
        ReceiveFlashLoanLocal memory v,
        address token,
        uint amountToRepay,
        uint swapPriceImpactTolerance0
    ) internal {
        ISwapper swapper = ISwapper(IPlatform(platform).swapper());
        uint requiredAmount = amountToRepay;
        {
            uint balance = IERC20(token).balanceOf(address(this));
            requiredAmount = amountToRepay > balance ? amountToRepay - balance : 0;
        }

        if (v.ptExpiredMode) {
            // Pendle market is expired
            // PT tokens should be swapped to asset as 1:1
            // We need to swap in so way that we receive amountToRepay on balance exactly

            // assume below that available collateral amount is always enough for the first swap
            // because we need to pay flash loan and then send not-zero amount of collateral to the user
            (ISwapper.PoolData[] memory route,) = swapper.buildRoute(token, v.collateralAsset);
            bool simpleMode = route.length == 1;
            if (simpleMode) {
                // Ex: PT => USDC. As soon as the market is expired, price 1:1 (in practice: 1 decimal can be lost)
                StrategyLib.swap(platform, v.collateralAsset, token, requiredAmount + 1, swapPriceImpactTolerance0);
            } else {
                // Ex: PT => stkscETH => scETH => WETH
                // PT => stkscETH is 1:1 but other conversions can have prices and price impact
                // We cannot swap larger amount and then swap remain amount back because the market is expired
                // So, let's swap in two steps
                // At first try to swap amount according to price (without taking price impact into account)
                // Then check balances and swap little more amount to get amountToRepay on balance

                uint amountToSwap = swapper.getPrice(token, v.collateralAsset, requiredAmount);
                StrategyLib.swap(platform, v.collateralAsset, token, amountToSwap, swapPriceImpactTolerance0);
            }

            uint balance = IERC20(token).balanceOf(address(this));
            requiredAmount = amountToRepay > balance ? amountToRepay - balance : 0;
        }

        if (requiredAmount != 0) {
            // We have collateral C = C1 + C2 where C1 is amount to withdraw, C2 is amount to swap to B (to repay)
            // We don't need to swap whole C, we can swap only C2 with same addon (i.e. 10%) for safety

            uint minCollateralToSwap = swapper.getPrice(
                token,
                v.collateralAsset,
                requiredAmount * (100_000 + swapPriceImpactTolerance0) / 100_000 // priceImpactTolerance has its own denominator
            );
            uint amountToSwap = Math.min(minCollateralToSwap, StrategyLib.balance(v.collateralAsset));

            // swap
            StrategyLib.swap(platform, v.collateralAsset, token, amountToSwap, swapPriceImpactTolerance0);
        }
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

        LeverageLendingLib.requestFlashLoan($, flashAssets, flashAmounts);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.None;
        (resultLtv,,,,,) = health(platform, $);
    }

    function realTvl(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $
    ) public view returns (uint tvl, bool trusted) {
        SiloAdvancedLib.CollateralDebtState memory
            debtState = getDebtState(platform, $.lendingVault, $.collateralAsset, $.borrowAsset, $.borrowingVault);
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
            uint pc = ISiloOracle(collateralOracle)
                .quote(10 ** IERC20Metadata(collateralConfig.token).decimals(), collateralConfig.token);
            uint pb = ISiloOracle(borrowOracle)
                .quote(10 ** IERC20Metadata(borrowConfig.token).decimals(), borrowConfig.token);
            priceCtoB = pc * 1e18 / pb;
            priceBtoC = pb * 1e18 / pc;
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
        if (tokenIn == TOKEN_WS && tokenOut == TOKEN_WANS) {
            //console.log('ws to wans swap');
            // check price of swap without impact
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            uint outBySwap = swapper.getPrice(tokenIn, tokenOut, amount);
            //console.log('amount out by swap', outBySwap);

            uint outByMint = IERC4626(TOKEN_WANS).convertToShares(amount);
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

        if (tokenIn == TOKEN_USDC && tokenOut == TOKEN_WSTKSCUSD) {
            //console.log('USDC to wstkscUSDC swap');
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            uint outBySwap = swapper.getPrice(tokenIn, tokenOut, amount);
            //console.log('amount out by swap', outBySwap);
            uint outByMint = IERC4626(tokenOut).convertToShares(amount);
            //console.log('amount out by mint', outByMint);

            if (outByMint > outBySwap * 99_90 / 100_00) {
                // mint scUSD
                IERC20(TOKEN_USDC).forceApprove(TOKEN_SCUSD, amount);
                ITeller(TELLER_SCUSD).deposit(TOKEN_USDC, amount, 0);
                // mint stkscUSD
                IERC20(TOKEN_SCUSD).forceApprove(TOKEN_STKSCUSD, amount);
                ITeller(TELLER_STKSCUSD).deposit(TOKEN_SCUSD, amount, 0);
                // mint wstkscUSD
                IERC20(TOKEN_STKSCUSD).forceApprove(TOKEN_WSTKSCUSD, amount);
                IERC4626(TOKEN_WSTKSCUSD).deposit(amount, address(this));
                //console.log('minted');
                return;
            }
        }

        if (tokenIn == TOKEN_WETH && tokenOut == TOKEN_WSTKSCETH) {
            //console.log('wETH to wstkscETH swap');
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            uint outBySwap = swapper.getPrice(tokenIn, tokenOut, amount);
            //console.log('amount out by swap', outBySwap);
            uint outByMint = IERC4626(tokenOut).convertToShares(amount);
            //console.log('amount out by mint', outByMint);

            if (outByMint > outBySwap * 99_50 / 100_00) {
                // mint scETH
                IERC20(TOKEN_WETH).forceApprove(TOKEN_SCETH, amount);
                ITeller(TELLER_SCETH).deposit(TOKEN_WETH, amount, 0);
                // mint stkscETH
                IERC20(TOKEN_SCETH).forceApprove(TOKEN_STKSCETH, amount);
                ITeller(TELLER_STKSCETH).deposit(TOKEN_SCETH, amount, 0);
                // mint wstkscETH
                IERC20(TOKEN_STKSCETH).forceApprove(TOKEN_WSTKSCETH, amount);
                IERC4626(TOKEN_WSTKSCETH).deposit(amount, address(this));
                //console.log('minted');
                return;
            }
        }

        if (tokenIn == TOKEN_USDC && tokenOut == TOKEN_SMSUSD) {
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            uint outBySwap = swapper.getPrice(tokenIn, tokenOut, amount);
            uint outByMint = IMainstreetMinter(MSUSD_MINTER).quoteMint(TOKEN_USDC, amount);

            if (outByMint > outBySwap * 99_50 / 100_00 && IMainstreetMinter(MSUSD_MINTER).isWhitelisted(address(this)))
            {
                // mint msUSD
                IERC20(TOKEN_USDC).forceApprove(MSUSD_MINTER, amount);
                IMainstreetMinter(MSUSD_MINTER).mint(TOKEN_USDC, amount, 0);
                uint balanceMsUsd = IERC20(TOKEN_MSUSD).balanceOf(address(this));

                // stake to smsUSD
                IERC20(TOKEN_MSUSD).forceApprove(TOKEN_SMSUSD, balanceMsUsd);
                IERC4626(TOKEN_SMSUSD).deposit(balanceMsUsd, address(this));

                return;
            }
        }

        StrategyLib.swap(platform, tokenIn, tokenOut, amount, priceImpactTolerance);
    }

    //region ------------------------------------- Deposit
    function depositAssets(
        address platform,
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

        // ensure that result LTV doesn't exceed max
        (uint maxLtv,,) = getLtvData(v.lendingVault, $.targetLeveragePercent);
        _ensureLtvValid($, platform, maxLtv);
    }

    function _deposit(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ILeverageLendingStrategy.LeverageLendingAddresses memory v,
        uint amountToDeposit
    ) internal {
        uint borrowAmount = _getDepositFlashAmount($, v, amountToDeposit);
        (address[] memory flashAssets, uint[] memory flashAmounts) = _getFlashLoanAmounts(borrowAmount, v.borrowAsset);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.Deposit;
        LeverageLendingLib.requestFlashLoan($, flashAssets, flashAmounts);
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
            * 
            // depositParam0 is used to move result leverage to targetValue.
            // Otherwise result leverage is higher the target value because of swap losses
            $.depositParam0 / INTERNAL_PRECISION / (10 ** IERC20Metadata(v.collateralAsset).decimals());
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

        if (receiver != address(this)) {
            IERC20(v.collateralAsset).safeTransfer(receiver, amountsOut[0]);
        }

        $base.total -= value;

        // ---------------------- Deposit the amount ~ value
        if (state.withdrawParam1 > INTERNAL_PRECISION) {
            _depositAfterWithdraw($, v, state.withdrawParam1, value);
        }

        // ensure that result LTV doesn't exceed max
        _ensureLtvValid($, platform, state.maxLtv);
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
            SiloAdvancedLib._deposit($, v, Math.min(maxAmountToWithdraw, balance));
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

        SiloAdvancedLib.CollateralDebtState memory debtState =
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

        uint targetLtv = Math.max(
            state.maxLtv,
            state.ltv * 1e18 / INTERNAL_PRECISION * 1003 / 1000 // todo move to config
        );

        uint[] memory flashAmounts = new uint[](1);
        flashAmounts[0] = collateralAmountToWithdraw * targetLtv / 1e18 * state.priceCtoB * state.withdrawParam0
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
            * (10 ** IERC20Metadata(v.borrowAsset).decimals()) / (10 ** IERC20Metadata(v.collateralAsset).decimals())
            / 1e18; // priceCtoB has decimals 18

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

    //endregion ------------------------------------- Withdraw

    //region ------------------------------------- Internal

    /// @notice ensure that result LTV doesn't exceed max
    function _ensureLtvValid(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address platform,
        uint maxLtv
    ) internal view {
        (uint ltv,,,,,) = health(platform, $);
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

    function _getLimitedAmount(uint amount, uint optionalLimit) internal pure returns (uint) {
        if (optionalLimit == 0) return amount;
        return Math.min(amount, optionalLimit);
    }

    function _isPtExpiredMode(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $
    ) internal view returns (bool) {
        // PT expired mode is used when the strategy is used with Pendle
        // and the PT tokens are expired, so we can swap them 1:1 to the asset
        return $.depositParam1 == COLLATERAL_IS_PT_EXPIRED_MARKET;
    }
    //endregion ------------------------------------- Internal
}
