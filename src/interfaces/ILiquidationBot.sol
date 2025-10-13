// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILiquidationBot {
    /// @notice User asset info: what is the balance of aTokens, stable and variable debt
    struct UserAssetInfo {
        address asset;
        uint currentATokenBalance;
        uint currentVariableDebt;
    }
    // uint currentStableDebt; // not used, we assume it's 0 always

    /// @notice Results of AAVE Pool.getUserAccountData(user)
    struct UserAccountData {
        uint totalCollateralBase;
        uint totalDebtBase;
        uint availableBorrowsBase;
        /// @notice decimals 4
        uint currentLiquidationThreshold;
        uint ltv;
        /// @notice Health factor. If it is below 1e18, the user can be liquidated
        uint healthFactor;
    }

    /// @notice User position that can be liquidated: what collateral and debt reserves, amounts
    struct UserPosition {
        address collateralReserve;
        address debtReserve;
        uint collateralAmount;
        uint debtAmount;
    }

    //region ----------------------------------------------------- Read functions

    /// @dev Init
    function initialize(address platform_) external;

    /// @notice Info: what assets the user has, what is the balance of aTokens, stable and variable debt
    function getUserAssetInfo(address aavePool, address user) external view returns (UserAssetInfo[] memory);

    /// @notice Info: current state of the user account
    function getUserAccountData(address aavePool, address user) external view returns (UserAccountData memory);

    /// @notice How much of {collateralAsset_} the bot will receive if it repays {repayAmount_} of {debtAsset_}
    /// in assumption that the user has {collateralAmount_} of collateral
    function getCollateralToReceive(
        address aavePool,
        address collateralAsset_,
        address debtAsset_,
        uint collateralAmount_,
        uint repayAmount_
    ) external view returns (uint collateralToReceive);

    /// @notice Calculate how much debt should be repaid to reach the target health factor
    function getRepayAmount(
        address aavePool,
        address collateralAsset_,
        address debtAsset_,
        ILiquidationBot.UserAccountData memory userAccountData_,
        uint targetHealthFactor_
    ) external view returns (uint repayAmount);

    /// @notice Returns true if the operator is whitelisted
    /// Multisig is always whitelisted.
    function whitelisted(address operator_) external view returns (bool);

    /// @notice Price impact tolerance. Denominator is 100_000.
    function priceImpactTolerance() external view returns (uint _priceImpactTolerance);

    /// @notice Address of the contract where profit will be sent
    function profitTarget() external view returns (address);

    /// @notice Get flash loan vault and its kind
    /// @return flashLoanVault Address of the vault that will provide flash loans
    /// @return  flashLoanKind Same values as in ILeverageLendingStrategy.FlashKind
    function getFlashLoanVault() external view returns (address flashLoanVault, uint flashLoanKind);

    /// @notice True if the given address is registered as wrapped meta vault
    function isWrappedMetaVault(address wrappedMetaVault_) external view returns (bool);

    /// @notice Target health factor for the users after liquidation
    function targetHealthFactor() external view returns (uint);

    //endregion ----------------------------------------------------- Read functions

    //region ----------------------------------------------------- Write functions

    /// @notice Set flash loan vault and its kind
    /// @param flashLoanKind Same values as in ILeverageLendingStrategy.FlashKind
    function setFlashLoanVault(address flashLoanVault, uint flashLoanKind) external;

    /// @notice Add or remove wrapped meta vault to/from the list of registered wrapped meta vaults
    function changeWrappedMetaVault(address wrappedMetaVault_, bool add_) external;

    /// @notice Set price impact tolerance. Denominator is 100_000.
    function setPriceImpactTolerance(uint priceImpactTolerance_) external;

    /// @notice Profit target - address of the contract where profit will be sent
    function setProfitTarget(address profitTarget_) external;

    /// @notice Add or remove operator from the whitelist
    function changeWhitelist(address operator_, bool add_) external;

    /// @notice Default target health factor for the users after liquidation
    /// This HF is used if liquidate(pool, users) is called
    /// or if liquidate(pool, users, type(uint).max) is called
    /// @param targetHealthFactor_ Target health factor, decimals 18, must be > 1e18
    /// 0 - means that max possible debt should be repaid (up to 50% of total debt)
    function setTargetHealthFactor(uint targetHealthFactor_) external;

    /// @notice Make liquidation, send profit to the registered contract
    /// @param aavePool Pool AAVE 3.0.2
    /// @param users List of users to liquidate (users with health factor < 1)
    function liquidate(address aavePool, address[] memory users) external;

    /// @param healthFactor Use type(uint).max to use default target health factor and 0 to use max possible repay
    function liquidate(address aavePool, address[] memory users, uint healthFactor) external;

    /// @notice Make liquidation, send profit to the registered contract
    /// @param users List of users to liquidate (users with health factor < 1)
    /// @param debtAsset Asset to be used for liquidation
    /// @param debtToCover Amounts of {asset} that should be re-payed for each user.
    /// Max 50% of total debt can be repaid. Max repay amount can be calculated using getRepayAmount()
    function liquidate(
        address aavePool,
        address[] memory users,
        address debtAsset,
        uint[] memory debtToCover
    ) external;

    //endregion ----------------------------------------------------- Write functions
}
