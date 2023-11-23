// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./IStrategy.sol";

/// @notice Vault core interface.
/// Derived implementations can be effective for building tokenized vaults with single or multiple underlying liquidity mining position.
/// Fungible, static non-fungible and actively re-balancing liquidity is supported, as well as single token liquidity provided to lending protocols.
/// Vaults can be used for active concentrated liquidity management and market making.
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
interface IVault is IERC165 {
    //region ----- Custom Errors -----
    error NotEnoughBalanceToPay();
    error FuseTrigger();
    error ExceedSlippage(uint mintToUser, uint minToMint);
    error ExceedSlippageExactAsset(address asset, uint mintToUser, uint minToMint);
    error ExceedMaxSupply(uint maxSupply);
    error NotEnoughAmountToInitSupply(uint mintAmount, uint initialShares);
    error WaitAFewBlocks();
    //endregion -- Custom Errors -----
    
    //region ----- Events -----

    event DepositAssets(address indexed account, address[] assets, uint[] amounts, uint mintAmount);
    event WithdrawAssets(address indexed account, address[] assets, uint sharesAmount, uint[] amountsOut);
    event HardWorkGas(uint gasUsed, uint gasCost, bool compensated);
    event DoHardWorkOnDepositChanged(bool oldValue, bool newValue);
    event MinTVLChanged(uint oldValue, uint newValue);
    event MaxSupply(uint maxShares);

    //endregion -- Events -----

    //region ----- Data types -----

    /// @title Vault Initialization Data
    /// @notice Data structure containing parameters for initializing a new vault.
    /// @dev This struct is commonly used as a parameter for the `initialize` function in vault contracts.
    /// @param platform Platform address providing access control, infrastructure addresses, fee settings, and upgrade capability.
    /// @param strategy Immutable strategy proxy used by the vault.
    /// @param name ERC20 name for the vault token.
    /// @param symbol ERC20 symbol for the vault token.
    /// @param tokenId NFT ID associated with the VaultManager.
    /// @param vaultInitAddresses Array of addresses used during vault initialization.
    /// @param vaultInitNums Array of uint values corresponding to initialization parameters.
    struct VaultInitializationData {
        address platform;
        address strategy;
        string name;
        string symbol;
        uint tokenId;
        address[] vaultInitAddresses;
        uint[] vaultInitNums;
    }

    /// @title Deposit Assets Data
    /// @notice Data structure containing parameters for function depositAssets to avoid stack too deep.
    /// @notice This structure use local variables. 
    struct DepositAssetsData {
        uint _totalSupply;
        uint totalValue;
        uint len;
        address[] assets;
        address underlying;
        uint[] amountsConsumed;
        uint value;
        uint mintAmount;
    }

    //endregion -- Data types -----

    //region ----- Read functions -----

    /// @notice Immutable vault type ID
    function VAULT_TYPE() external view returns (string memory);

    /// @return Required unique init addresses
    //slither-disable-next-line naming-convention
    function UNIQUE_INIT_ADDRESSES() external view returns (uint);

    /// @return Required unique init nums
    //slither-disable-next-line naming-convention
    function UNIQUE_INIT_NUMS() external view returns (uint);

    /// @return uniqueInitAddresses Return required unique init addresses
    /// @return uniqueInitNums Return required unique init nums
    function getUniqueInitParamLength() external view returns(uint uniqueInitAddresses, uint uniqueInitNums);

    /// @notice Vault type extra data
    /// @return Vault type color, background color and other extra data
    function extra() external view returns (bytes32);

    /// @notice Immutable strategy proxy used by the vault
    /// @return Linked strategy
    function strategy() external view returns (IStrategy);

    /// @notice Max supply of shares in the vault.
    /// Since the starting share price is $1, this ceiling can be considered as an approximate TVL limit.
    /// @return Max total supply of vault
    function maxSupply() external view returns (uint);

    /// @dev VaultManager token ID. This tokenId earn feeVaultManager provided by Platform.
    function tokenId() external view returns (uint);

    /// @dev Trigger doHardwork on invest action. Enabled by default.
    function doHardWorkOnDeposit() external view returns(bool);

    /// @dev USD price of share with 18 decimals.
    ///      ONLY FOR OFF-CHAIN USE.
    ///      Not trusted vault share price can be manipulated.
    /// @return price Price of 1e18 shares with 18 decimals precision
    /// @return trusted True means oracle price, false means AMM spot price
    function price() external view returns (uint price, bool trusted);

    /// @dev USD price of assets managed by strategy with 18 decimals
    ///      ONLY FOR OFF-CHAIN USE.
    ///      Not trusted TVL can be manipulated.
    /// @return tvl_ Total USD value of final assets in vault
    /// @return trusted True means TVL calculated based only on oracle prices, false means AMM spot price was used.
    function tvl() external view returns (uint tvl_, bool trusted);

    /// @notice Show minimum TVL for compensate if vault has not enough ETH
    /// @return Minimum TVL for compensate.
    function minTVL() external view returns (uint);

    /// @dev Calculation of consumed amounts, shares amount and liquidity/underlying value for provided available amounts of strategy assets
    /// @param assets_ Assets suitable for vault strategy. Can be strategy assets, underlying asset or specific set of assets depending on strategy logic.
    /// @param amountsMax Available amounts of assets_ that user wants to invest in vault
    /// @return amountsConsumed Amounts of strategy assets that can be deposited by providing amountsMax
    /// @return sharesOut Amount of vault shares that will be minted
    /// @return valueOut Liquidity value or underlying token amount that will be received by the strategy
    function previewDepositAssets(address[] memory assets_, uint[] memory amountsMax) external view returns (uint[] memory amountsConsumed, uint sharesOut, uint valueOut);

    /// @notice All available data on the latest declared APR (annual percentage rate)
    /// @return totalApr Total APR of investing money to vault. 18 decimals: 1e18 - +100% per year.
    /// @return strategyApr Strategy investmnt APR declared on last HardWork.
    /// @return assetsWithApr Assets with underlying APR
    /// @return assetsAprs Underlying APR of asset
    function getApr() external view returns (uint totalApr, uint strategyApr, address[] memory assetsWithApr, uint[] memory assetsAprs);

    //endregion -- Read functions -----

    //region ----- Write functions -----

    /// @dev Deposit final assets (pool assets) to the strategy and minting of vault shares.
    ///      If the strategy interacts with a pool or farms through an underlying token, then it will be minted.
    ///      Emits a {DepositAssets} event with consumed amounts.
    /// @param assets_ Assets suitable for the strategy. Can be strategy assets, underlying asset or specific set of assets depending on strategy logic.
    /// @param amountsMax Available amounts of assets_ that user wants to invest in vault
    /// @param minSharesOut Slippage tolerance. Minimal shares amount which must be received by user.
    /// @param receiver Receiver of deposit. If receiver is zero address, receiver is msg.sender.
    function depositAssets(address[] memory assets_, uint[] memory amountsMax, uint minSharesOut, address receiver) external;

    /// @dev Burning shares of vault and obtaining strategy assets.
    /// @param assets_ Assets suitable for the strategy. Can be strategy assets, underlying asset or specific set of assets depending on strategy logic.
    /// @param amountShares Shares amount for burning
    /// @param minAssetAmountsOut Slippage tolerance. Minimal amounts of strategy assets that user must receive.
    function withdrawAssets(address[] memory assets_, uint amountShares, uint[] memory minAssetAmountsOut) external;

    /// @dev Setting of vault capacity
    /// @param maxShares If totalSupply() exceeds this value, deposits will not be possible
    function setMaxSupply(uint maxShares) external;

    /// @dev If activated will call doHardWork on strategy on some deposit actions
    /// @param value HardWork on deposit is enabled
    function setDoHardWorkOnDeposit(bool value) external;

    /// @notice Initialization function for the vault.
    /// @dev This function is usually called by the Factory during the creation of a new vault.
    /// @param vaultInitializationData Data structure containing parameters for vault initialization.
    function initialize(
        VaultInitializationData memory vaultInitializationData
    ) external;

    /// @dev Calling the strategy HardWork by operator with optional compensation for spent gas from the vault balance
    function doHardWork() external;

    /// @notice Update new minimum TVL for compansate.
    /// @param value New minimum TVL for compensate.
    function setMinTVL(uint value) external;

    //endregion -- Write functions -----

}
