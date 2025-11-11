// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "../../interfaces/ISwapper.sol";
import "./StrategyLib.sol";

library ALMFCalcLib {
    /// @dev 100_00 is 1.0 or 100%
    uint public constant INTERNAL_PRECISION = 100_00;

    struct StaticData {
        /// @notice Price of collateral asset in USD, decimals 18
        uint priceC;
        /// @notice Price of borrow asset in USD, decimals 18
        uint priceB;
        uint8 decimalsC;
        uint8 decimalsB;
    }

    struct State {
        uint collateralBase; // collateral amount in base asset
        uint debtBase;       // debt amount in base asset
        uint targetLeverage; // target leverage, INTERNAL_PRECISION
        uint swapFee;        // swap fee, INTERNAL_PRECISION
        uint flashFee;      // flash loan fee, INTERNAL_PRECISION
        StaticData data;
    }

//region ------------------------------------- Deposit logic
    /// @notice Calculate minimum additional amount to deposit to reach target leverage
    /// @param targetLeverage Target leverage, INTERNAL_PRECISION
    /// @param collateralBase Current collateral amount in base asset
    /// @param debtBase Current debt amount in base asset
    /// @return Additional amount to deposit in base asset.
    /// @dev Formula: A_min = TL * D0 / (TL - 1) - C0
    function aMin(uint targetLeverage, uint collateralBase, uint debtBase) internal pure returns (uint) {
        // we assume that current leverage is less than the target leverage and should be increased
        // we assume that targetLeverage is always greater than INTERNAL_PRECISION (1.0)
        return (targetLeverage * debtBase) / (targetLeverage - INTERNAL_PRECISION) - debtBase;
    }

    /// @notice Split deposit amount on two parts: amount to deposit as collateral and amount to be used to repay
    /// @param amount Total amount to deposit in base asset
    /// @param targetLeverage Target leverage, INTERNAL_PRECISION
    /// @param collateralBase Current collateral amount in base asset
    /// @param debtBase Current debt amount in base asset
    /// @param swapFee Swap fee, INTERNAL_PRECISION
    /// @return aD Amount to deposit as collateral in base asset
    /// @return aR Amount to be used to repay debt in base asset
    /// @dev Formula: A_r = [ TL*D0 - (TL - 1)*(C0 + A) ]  /  [ 1 - TL*s ]
    function splitDepositAmount(uint amount, uint targetLeverage, uint collateralBase, uint debtBase, uint swapFee) internal pure returns (uint aD, uint aR) {
        int arInt = (int(targetLeverage * debtBase) - int(targetLeverage - INTERNAL_PRECISION) * int(collateralBase + amount))
            / (int(INTERNAL_PRECISION) - int(targetLeverage * swapFee / INTERNAL_PRECISION));
        aR = arInt > 0 ? uint(arInt) : 0;
        aD = amount > aR ? amount - aR : 0;
    }

//endregion ------------------------------------- Deposit logic

//region ------------------------------------- Withdraw logic
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

    function collateralToBase(uint amountC, uint priceC, uint8 decimalsC) internal pure returns (uint) {
        return (amountC * priceC) / (10 ** decimalsC);
    }

    function borrowToBase(uint amountB, uint priceB, uint8 decimalsB) internal pure returns (uint) {
        return (amountB * priceB) / (10 ** decimalsB);
    }

    function baseToCollateral(uint amountBase, uint priceC, uint8 decimalsC) internal pure returns (uint) {
        return (amountBase * (10 ** decimalsC)) / priceC;
    }

    function baseToBorrow(uint amountBase, uint priceB, uint8 decimalsB) internal pure returns (uint) {
        return (amountBase * (10 ** decimalsB)) / priceB;
    }
//endregion ------------------------------------- State

}