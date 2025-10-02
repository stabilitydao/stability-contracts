// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILiquidationBot {
    /// @dev Init
    function initialize(address platform_) external;

    /// @notice Make liquidation, send profit to the registered contract
    /// @param addressProvider Aave data provider for AAVE 3.0.2
    /// @param users List of users to liquidate (users with health factor < 1)
    function liquidate(address addressProvider, address[] memory users) external;

    /// @notice Returns true if the operator is whitelisted
    /// Multisig is always whitelisted.
    function whitelisted(address operator_) external view returns (bool);

    /// @notice Price impact tolerance. Denominator is 100_000.
    function getPriceImpactTolerance() external view returns (uint priceImpactTolerance);

    /// @notice Address of the contract where profit will be sent
    function getProfitTarget() external view returns (address);

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
