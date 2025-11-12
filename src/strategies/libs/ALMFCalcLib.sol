// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {StrategyLib} from "./StrategyLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library ALMFCalcLib {
    /// @dev 100_00 is 100%
    uint public constant INTERNAL_PRECISION = 100_00;

    /// @notice Static data required to make deposit/withdraw calculations
    struct StaticData {
        address platform;

        /// @notice Address provider of AAVE. Assume that both assets have the same pool and the same provider
        address addressProvider;

        address collateralAsset;
        address borrowAsset;
        address lendingVault;
        address borrowingVault;
        address flashLoanVault;
        uint flashLoanKind;

        /// @notice Price of collateral asset in USD, decimals 18
        uint priceC18;
        /// @notice Price of borrow asset in USD, decimals 18
        uint priceB18;

        /// @notice Decimals of collateral asset
        uint8 decimalsC;
        /// @notice Decimals of borrow asset
        uint8 decimalsB;

        /// @notice max swap fee from strategy config, decimals 18
        uint swapFee18;
        /// @notice flash loan fee from selected flash loan vault, decimals 18
        uint flashFee18;

        /// @notice minimum target leverage from farm config, INTERNAL_PRECISION
        uint minTargetLeverage;

        /// @notice maximum target leverage from farm config, INTERNAL_PRECISION
        uint maxTargetLeverage;
    }

    struct State {
        /// @notice collateral amount in base asset (USD, 18 decimals)
        uint collateralBase;

        /// @notice debt amount in base asset (USD, 18 decimals)
        uint debtBase;

        /// @notice Current user LTV in AAVE, INTERNAL_PRECISION
        uint ltv;

        /// @notice Health factor, decimals 18; unhealthy if less than 1e18
        uint healthFactor;
}

//region ------------------------------------- Deposit logic

    /// @notice Split deposit amount on two parts: amount to deposit as collateral and amount to be used to repay
    /// @param amount Total amount to deposit in base asset
    /// @param targetLeverage Target leverage, INTERNAL_PRECISION
    /// @param collateralBase Current collateral amount in base asset
    /// @param debtBase Current debt amount in base asset
    /// @param swapFee18 Swap fee (percent), decimals 18
    /// @return aD Amount to deposit as collateral in base asset
    /// @return aR Amount to be used to repay debt in base asset
    /// @dev Formula: A_r = [ TL*D0 - (TL - 1)*(C0 + A) ]  /  [ 1 - TL*s ]
    function splitDepositAmount(uint amount, uint targetLeverage, uint collateralBase, uint debtBase, uint swapFee18) internal pure returns (uint aD, uint aR) {
        int arInt = (int(targetLeverage * debtBase) - int(targetLeverage - INTERNAL_PRECISION) * int(collateralBase + amount))
            / (int(INTERNAL_PRECISION) - int(targetLeverage * swapFee18 / 1e18));
        aR = arInt > 0 ? uint(arInt) : 0;
        aD = amount > aR ? amount - aR : 0;
    }

//endregion ------------------------------------- Deposit logic

//region ------------------------------------- Withdraw logic
    /// @notice Calculate F and C1 amounts in assumption that all fees are zero (= user takes all losses on himself)
    /// @param valueToWithdraw Value that user is going to withdraw, in USD, decimals 18
    /// @return flashAmount Flash loan amount in borrow asset
    /// @return collateralToWithdraw Amount of collateral to withdraw from aave in collateral asset
    function calcWithdrawAmounts(uint valueToWithdraw, uint leverageAdj, StaticData memory data, State memory state) internal pure returns (uint flashAmount, uint collateralToWithdraw) {
        //  state.collateralBase  — initial collateral (in base units)
        //  state.debtBase  — initial debt (same units)
        //  valueToWithdraw   — amount the user must receive (user payout, formerly “value”)
        //  La  — adjusted target leverage (L_adj)
        //  LTVa — target post-operation LTV = (La - 1) / La
        //  s   — swap loss fraction (e.g. 0.015)
        //  f   — flash-loan fee fraction (e.g. 0.005)
        //  α — coefficient linking required collateral for swap and F:
        //     α = (1 + f) / (1 - s) = 1 (all losses belong to the user, so we should use s = 0, f = 0 here)
        //  β = α * LTVa
        //  C1 — amount of collateral withdrawn from the pool
        //  F  — flash-loan size in borrow-asset units

        uint ltvAdj = INTERNAL_PRECISION - INTERNAL_PRECISION / leverageAdj;
        uint f = (state.debtBase - ltvAdj * state.collateralBase + ltvAdj * valueToWithdraw ) / (1 - ltvAdj);
        uint c1 = (valueToWithdraw + state.debtBase - ltvAdj * state.collateralBase ) / (1 - ltvAdj);

        return (
            _baseToBorrow(f, data.priceB18, data.decimalsB),
            _baseToCollateral(c1, data.priceC18, data.decimalsC)
        );
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
        uint minCollateralToSwap = swapper.getPrice(
            token,
            collateralAsset,
            requiredAmount * (100_000 + 2 * priceImpactTolerance) / 100_000
        ); // priceImpactTolerance has its own denominator

        return Math.min(minCollateralToSwap, StrategyLib.balance(collateralAsset));
    }

    function _balanceWithoutRewards(address borrowAsset, uint rewardsAmount) internal view returns (uint) {
        uint balance = StrategyLib.balance(borrowAsset);
        return balance > rewardsAmount ? balance - rewardsAmount : 0;
    }

    function _getLimitedAmount(uint amount, uint optionalLimit) internal pure returns (uint) {
        if (optionalLimit == 0) return amount;
        return Math.min(amount, optionalLimit);
    }
//endregion ------------------------------------- Withdraw logic

//region ------------------------------------- State
    /// @notice Calculate current leverage
    /// @param collateralBase Current collateral amount in base asset
    /// @param debtBase Current debt amount in base asset
    /// @return Current leverage, INTERNAL_PRECISION
    function getLeverage(uint collateralBase, uint debtBase) internal pure returns (uint) {
        if (collateralBase == 0) {
            return 0;
        }
        return (collateralBase * INTERNAL_PRECISION) / (collateralBase - debtBase);
    }

    /// @notice Calculate loan-to-value ratio (LTV) from leverage
    /// @param leverage Leverage, INTERNAL_PRECISION
    /// @return LTV, INTERNAL_PRECISION
    function getLtv(uint leverage) internal pure returns (uint) {
        if (leverage <= INTERNAL_PRECISION) {
            return 0;
        }
        return INTERNAL_PRECISION - INTERNAL_PRECISION / leverage;
    }

    function ltvToLeverage(uint ltv) internal pure returns (uint) {
        return INTERNAL_PRECISION / (INTERNAL_PRECISION - ltv);
    }

    /// @notice Calculate collateral balance in base asset (USD, 18 decimals)
    function collateralToBase(uint amount, ALMFCalcLib.StaticData memory data) internal pure returns (uint balance) {
        balance = _collateralToBase(amount, data.priceC18, data.decimalsC);
    }
    function borrowToBase(uint amount, ALMFCalcLib.StaticData memory data) internal pure returns (uint balance) {
        balance = _borrowToBase(amount, data.priceB18, data.decimalsB);
    }

    function baseToCollateral(uint amountBase, ALMFCalcLib.StaticData memory data) internal pure returns (uint) {
        return _baseToCollateral(amountBase, data.priceC18, data.decimalsC);
    }

    function baseToBorrow(uint amountBase, ALMFCalcLib.StaticData memory data) internal pure returns (uint) {
        return _baseToBorrow(amountBase, data.priceB18, data.decimalsB);
    }


    function _collateralToBase(uint amountC, uint priceC18, uint8 decimalsC) internal pure returns (uint) {
        return Math.mulDiv(amountC, priceC18, 10 ** decimalsC);
    }

    function _borrowToBase(uint amountB, uint priceB18, uint8 decimalsB) internal pure returns (uint) {
        return Math.mulDiv(amountB, priceB18, 10 ** decimalsB);
    }

    function _baseToCollateral(uint amountBase, uint priceC18, uint8 decimalsC) internal pure returns (uint) {
        return Math.mulDiv(amountBase, 10 ** decimalsC, priceC18);
    }

    function _baseToBorrow(uint amountBase, uint priceB18, uint8 decimalsB) internal pure returns (uint) {
        return Math.mulDiv(amountBase, 10 ** decimalsB, priceB18);
    }
//endregion ------------------------------------- State

}