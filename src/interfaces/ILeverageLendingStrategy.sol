// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILeverageLendingStrategy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event LeverageLendingHardWork(
        int realApr, int earned, uint realTvl, uint duration, uint realSharePrice, uint supplyApr, uint borrowApr
    );
    event LeverageLendingHealth(uint ltv, uint leverage);
    event TargetLeveragePercent(uint value);
    event UniversalParams(uint[] params);
    event UniversalAddresses(address[] addresses);

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
        /// @dev Universal configurable param 0 for depositAssets
        uint depositParam0;
        /// @dev Universal configurable param 1 for depositAssets
        uint depositParam1;
        /// @dev Universal configurable param 0 for withdrawAssets
        /// @dev SiL, SiAL: withdrawParam0 allows to regulate flash amount in default withdraw
        uint withdrawParam0;
        /// @dev Universal configurable param 1 for withdrawAssets
        /// @dev SiL, SiAL: withdrawParam1 allows to regulate/disable deposit after withdraw
        uint withdrawParam1;
        /// @dev Universal configurable param 0 for increase LTV
        uint increaseLtvParam0;
        /// @dev Universal configurable param 1 for increase LTV
        uint increaseLtvParam1;
        /// @dev Universal configurable param 0 for decrease LTV
        uint decreaseLtvParam0;
        /// @dev Universal configurable param 1 for decrease LTV
        uint decreaseLtvParam1;
        /// @dev Swap price impact tolerance on enter/exit
        uint swapPriceImpactTolerance0;
        /// @dev Swap price impact tolerance on re-balance debt
        uint swapPriceImpactTolerance1;
        /// @notice Flash loan kind. 0 - balancer v2 (paid), 1 - balancer v3 (free)
        uint flashLoanKind;
        /// @dev Universal address 1. SiL uses it to store flash loan vault address for borrow asset
        address universalAddress1;
        /// @dev Universal configurable param 2 for withdrawAssets
        /// @dev SiL, SiAL: withdrawParam1 allows to regulate withdraw-through-increasing-ltv
        uint withdrawParam2;
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
        uint targetLeveragePercent;
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
        /// @notice All available balances are used
        IncreaseLtv,
        /// @notice Amounts of collateral and borrow that can be used are limited through temp vars
        IncreaseLtvLimited
    }

    enum FlashLoanKind {
        /// @notice Balancer V2
        Default_0,
        BalancerV3_1,
        UniswapV3_2,
        AlgebraV4_3
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Re-balance debt
    /// @param newLtv Target LTV after re-balancing with 4 decimals. 90_00 is 90%.
    /// @return resultLtv LTV after re-balance. For static calls.
    /// @return resultSharePrice Share price after applying rebalance debt
    function rebalanceDebt(uint newLtv, uint minSharePrice) external returns (uint resultLtv, uint resultSharePrice);

    /// @notice Change target leverage percent
    /// @param value Value with 4 decimals, 90_00 is 90%.
    function setTargetLeveragePercent(uint value) external;

    /// @notice Change universal configurable params
    function setUniversalParams(uint[] memory params, address[] memory addresses) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @notice Get universal configurable params
    function getUniversalParams() external view returns (uint[] memory params, address[] memory addresses);

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
