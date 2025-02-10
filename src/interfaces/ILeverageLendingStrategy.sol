// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ILeverageLendingStrategy {
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
        Withdraw
    }

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

    function state()
        external
        view
        returns (uint ltv, uint leverage, uint collateralAmount, uint debtAmount, uint targetLeveragePercent);
}
