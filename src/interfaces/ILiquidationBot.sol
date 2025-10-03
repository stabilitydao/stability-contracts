// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILiquidationBot {

    struct UserAssetInfo {
        address asset;
        uint currentATokenBalance;
        uint currentStableDebt;
        uint currentVariableDebt;
    }

    struct UserAccountData {
        uint totalCollateralBase;
        uint totalDebtBase;
        uint availableBorrowsBase;
        uint currentLiquidationThreshold;
        uint ltv;
        uint healthFactor;
    }

    struct UserPosition {
        address collateralReserve;
        address debtReserve;
        uint collateralAmount;
        uint debtAmount;
    }

    /// @dev Init
    function initialize(address platform_) external;

    /// @notice Info: what assets the user has, what is the balance of aTokens, stable and variable debt
    function getUserAssetInfo(address aavePool, address user) external view returns (UserAssetInfo[] memory);

    /// @notice Info: current state of the user account
    function getUserAccountData(address aavePool, address user) external view returns (UserAccountData memory);

    /// @notice Make liquidation, send profit to the registered contract
    /// @param aavePool Pool AAVE 3.0.2
    /// @param users List of users to liquidate (users with health factor < 1)
    function liquidate(address aavePool, address[] memory users) external;

    /// @notice Returns true if the operator is whitelisted
    /// Multisig is always whitelisted.
    function whitelisted(address operator_) external view returns (bool);

    /// @notice Price impact tolerance. Denominator is 100_000.
    function priceImpactTolerance() external view returns (uint priceImpactTolerance);

    /// @notice Address of the contract where profit will be sent
    function profitTarget() external view returns (address);

    /// @notice Get flash loan vault and its kind
    /// @return flashLoanVault Address of the vault that will provide flash loans
    /// @return  flashLoanKind Same values as in ILeverageLendingStrategy.FlashKind
    function getFlashLoanVault() external view returns (address flashLoanVault, uint flashLoanKind);

    /// @notice Set flash loan vault and its kind
    /// @param flashLoanKind Same values as in ILeverageLendingStrategy.FlashKind
    function setFlashLoanVault(address flashLoanVault, uint flashLoanKind) external;

    /// @notice Set price impact tolerance. Denominator is 100_000.
    function setPriceImpactTolerance(uint priceImpactTolerance) external;

    /// @notice Profit target - address of the contract where profit will be sent
    function setProfitTarget(address profitTarget) external;

    /// @notice Add or remove operator from the whitelist
    function changeWhitelist(address operator_, bool add_) external;
}
