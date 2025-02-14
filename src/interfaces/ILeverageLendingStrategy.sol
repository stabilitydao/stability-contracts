// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ILeverageLendingStrategy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event LeverageLendingHardWork(
        int realApr, int earned, uint realTvl, uint duration, uint realSharePrice, uint supplyApr, uint borrowApr
    );
    event LeverageLendingHealth(uint ltv, uint leverage);
    event TargetLeveragePercent(uint value);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.LeverageLendingBase
    struct LeverageLendingBaseStorage {
        // init immutable params
        address collateralAsset;
        address borrowAsset;
        address lendingVault;
        address borrowingVault;
        address flashLoanVault;
        address helper;
        // temp vars
        CurrentAction tempAction;
        uint tempBorrowAmount;
        uint tempCollateralAmount;
        // configurable params
        /// @dev Percent of max leverage. 90_00 is 90%.
        uint targetLeveragePercent;
    }

    struct LeverageLendingStrategyBaseInitParams {
        string strategyId;
        address platform;
        address vault;
        address collateralAsset;
        address borrowAsset;
        address lendingVault;
        address borrowingVault;
        address flashLoanVault;
        address helper;
    }

    struct LeverageLendingAddresses {
        address collateralAsset;
        address borrowAsset;
        address lendingVault;
        address borrowingVault;
    }

    enum CurrentAction {
        None,
        Deposit,
        Withdraw,
        DecreaseLtv,
        IncreaseLtv
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Re-balance debt
    /// @param newLtv Target LTV after re-balancing with 4 decimals. 90_00 is 90%.
    /// @return resultLtv LTV after re-balance. For static calls.
    function rebalanceDebt(uint newLtv) external returns (uint resultLtv);

    /// @notice Change target leverage percent
    /// @param value Value with 4 decimals, 90_00 is 90%.
    function setTargetLeveragePercent(uint value) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Difference between collateral and debt
    /// @return tvl USD amount of user deposited assets
    /// @return trusted True if only oracle prices was used for calculation.
    function realTvl() external view returns (uint tvl, bool trusted);

    /// @notice Vault share price of difference between collateral and debt
    /// @return sharePrice USD amount of share price of user deposited assets
    /// @return trusted True if only oracle prices was used for calculation.
    function realSharePrice() external view returns (uint sharePrice, bool trusted);

    /// @notice Show leverage main data
    /// @return ltv Current LTV with 4 decimals. 90_00 is 90%.
    /// @return maxLtv Maximum LTV with 4 decimals. 90_00 is 90%.
    /// @return leverage Current leverage multiplier with 4 decimals
    /// @return collateralAmount Current amount of collateral asset (strategy asset)
    /// @return debtAmount Current debt of borrowed asset
    /// @return targetLeveragePercent Configurable percent of max leverage. 90_00 is 90%.
    function health()
        external
        view
        returns (
            uint ltv,
            uint maxLtv,
            uint leverage,
            uint collateralAmount,
            uint debtAmount,
            uint targetLeveragePercent
        );

    /// @notice Show APRs
    /// @return supplyApr APR of supplying with 5 decimals.
    /// @return borrowApr APR of borrowing with 5 decimals.
    function getSupplyAndBorrowAprs() external view returns (uint supplyApr, uint borrowApr);
}
