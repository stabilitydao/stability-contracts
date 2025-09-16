// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IFrontend {
    /// @notice Platform address
    // slither-disable-next-line naming-convention
    function PLATFORM() external view returns (address);

    /// @notice Version of Frontend contract
    function VERSION() external view returns (string memory);

    /// @notice Main vaults data
    /// @param start Start vault number on page
    /// @param pageSize Size of page
    /// @return total Total vaults in current chain
    /// The output values are matched by index in the arrays.
    /// @return vaultAddress Vault addresses
    /// @return name Vault name
    /// @return symbol Vault symbol
    /// @return vaultType Vault type ID string
    /// @return sharePrice Current vault share price in USD. 18 decimals
    /// @return tvl Current vault TVL in USD. 18 decimals
    /// @return strategy Linked strategy address
    /// @return strategyId Strategy logic ID string
    /// @return strategySpecific Strategy specific name
    function vaults(
        uint start,
        uint pageSize
    )
        external
        view
        returns (
            uint total,
            address[] memory vaultAddress,
            string[] memory name,
            string[] memory symbol,
            string[] memory vaultType,
            uint[] memory sharePrice,
            uint[] memory tvl,
            address[] memory strategy,
            string[] memory strategyId,
            string[] memory strategySpecific
        );

    /// @notice Get user balance of all supported assets with asset prices
    /// @param userAccount Address of account to query balances
    /// @param start Start asset number on page
    /// @param pageSize Size of page
    /// @return total Total assets
    /// @return asset Asset addresses
    /// @return assetPrice USD price of asset. Index of asset same as in previous array.
    /// @return assetUserBalance User balance of token. Index of token same as in previous array.
    function getBalanceAssets(
        address userAccount,
        uint start,
        uint pageSize
    )
        external
        view
        returns (uint total, address[] memory asset, uint[] memory assetPrice, uint[] memory assetUserBalance);

    /// @notice Get user balance of vaults with vault share prices
    /// @param userAccount Address of account to query balances
    /// @param start Start asset number on page
    /// @param pageSize Size of page
    /// @return total Total vaults
    /// @return vault Deployed vaults
    /// @return vaultSharePrice Price of 1.0 vault share. Index of vault same as in previous array.
    /// @return vaultUserBalance User balance of vault. Index of vault same as in previous array.
    function getBalanceVaults(
        address userAccount,
        uint start,
        uint pageSize
    )
        external
        view
        returns (uint total, address[] memory vault, uint[] memory vaultSharePrice, uint[] memory vaultUserBalance);

    /// @notice Available variants of new vault for creating.
    /// @param startStrategy Start number of strategy to query
    /// @param step Size of page
    /// @return totalStrategies Total strategies in chain
    /// @return desc Descriptions of the strategy for making money
    /// @return vaultType Vault type strings. Output values are matched by index with previous array.
    /// @return strategyId Strategy logic ID strings. Output values are matched by index with previous array.
    /// @return initIndexes Map of start and end indexes in next 5 arrays. Output values are matched by index with previous array.
    ///                 [0] Start index in vaultInitAddresses
    ///                 [1] End index in vaultInitAddresses
    ///                 [2] Start index in vaultInitNums
    ///                 [3] End index in vaultInitNums
    ///                 [4] Start index in strategyInitAddresses
    ///                 [5] End index in strategyInitAddresses
    ///                 [6] Start index in strategyInitNums
    ///                 [7] End index in strategyInitNums
    ///                 [8] Start index in strategyInitTicks
    ///                 [9] End index in strategyInitTicks
    /// @return vaultInitAddresses Vault initialization addresses for deployVaultAndStrategy method for all building variants.
    /// @return vaultInitNums Vault initialization uint numbers for deployVaultAndStrategy method for all building variants.
    /// @return strategyInitAddresses Strategy initialization addresses for deployVaultAndStrategy method for all building variants.
    /// @return strategyInitNums Strategy initialization uint numbers for deployVaultAndStrategy method for all building variants.
    /// @return strategyInitTicks Strategy initialization int24 ticks for deployVaultAndStrategy method for all building variants.
    function whatToBuild(
        uint startStrategy,
        uint step
    )
        external
        view
        returns (
            uint totalStrategies,
            string[] memory desc,
            string[] memory vaultType,
            string[] memory strategyId,
            uint[10][] memory initIndexes,
            address[] memory vaultInitAddresses,
            uint[] memory vaultInitNums,
            address[] memory strategyInitAddresses,
            uint[] memory strategyInitNums,
            int24[] memory strategyInitTicks
        );
}
