// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library ALMFCalcLib {
    /// @dev 100_00 is 1.0 or 100%
    uint public constant INTERNAL_PRECISION = 100_00;

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
        aR = (targetLeverage * debtBase - (targetLeverage - INTERNAL_PRECISION) * (collateralBase + amount))
            / (INTERNAL_PRECISION - targetLeverage * swapFee / INTERNAL_PRECISION);
        aD = amount - aR;
    }



//endregion ------------------------------------- Deposit logic

}