// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev Combining oracle and DeX spot prices
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
interface IPriceReader {
    //region ----- Events -----
    event AdapterAdded(address adapter);
    event AdapterRemoved(address adapter);
    event VaultWithSafeSharePriceAdded(address vault);
    event VaultWithSafeSharePriceRemoved(address vault);
    //endregion -- Events -----

    //region --------------------------- Errors
    error NotWhitelistedTransientCache();
    //endregion --------------------------- Errors


    /// @notice Price of asset
    /// @dev Price of 1.0 amount of asset in USD
    /// @param asset Address of asset
    /// @return price USD price with 18 decimals
    /// @return trusted Price from oracle
    function getPrice(address asset) external view returns (uint price, bool trusted);

    /// @notice Price of vault share
    /// @dev Price of 1.0 amount of vault token
    /// @param vault Address of vault
    /// @return price USD price with 18 decimals
    /// @return safe Safe to use this price on-chain
    function getVaultPrice(address vault) external view returns (uint price, bool safe);

    /// @notice Get USD price of specified assets and amounts
    /// @param assets_ Addresses of assets
    /// @param amounts_ Amount of asset. Index of asset same as in previous parameter.
    /// @return total Total USD value with 18 decimals
    /// @return assetAmountPrice USD price of asset amount. Index of assetAmountPrice same as in assets_ parameters.
    /// @return assetPrice USD price of asset. Index of assetAmountPrice same as in assets_ parameters.
    /// @return trusted True if only oracle prices was used for calculation.
    function getAssetsPrice(
        address[] memory assets_,
        uint[] memory amounts_
    ) external view returns (uint total, uint[] memory assetAmountPrice, uint[] memory assetPrice, bool trusted);

    /// @notice Get vaults that have organic safe share price that can be used on-chain
    function vaultsWithSafeSharePrice() external view returns (address[] memory vaults);

    /// @notice Add oracle adapter to PriceReader
    /// Only operator (multisig is operator too) can add adapter
    /// @param adapter_ Address of price oracle proxy
    function addAdapter(address adapter_) external;

    /// @notice Remove oracle adapter from PriceReader
    /// Only operator (multisig is operator too) can add adapter
    /// @param adapter_ Address of price oracle proxy
    function removeAdapter(address adapter_) external;

    /// @notice Add vaults that have organic safe share price that can be used on-chain
    /// Only operator (multisig is operator too) can add adapter
    /// @param vaults Addresses of vaults
    function addSafeSharePrices(address[] memory vaults) external;

    /// @notice Remove vaults that have organic safe share price that can be used on-chain
    /// Only operator (multisig is operator too) can add adapter
    /// @param vaults Addresses of vaults
    function removeSafeSharePrices(address[] memory vaults) external;

    /// @notice Check if the user is whitelisted for using transient cache
    function whitelistTransientCache(address user_) external view returns (bool);

    /// @notice Add user to whitelist of users allowed to use the transient cache
    function changeWhitelistTransientCache(address user, bool add) external;

    /// @notice Save asset price to transient cache
    /// @param asset Pass 0 to clear the cache
    function preCalculatePriceTx(address asset) external;

    /// @notice Save vault price to transient cache
    /// Second call with the same vault will be ignored and won't not change the price
    /// @param vault Pass 0 to clear the cache
    function preCalculateVaultPriceTx(address vault) external;
}
