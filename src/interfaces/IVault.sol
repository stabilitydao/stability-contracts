// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./IStrategy.sol";

/// @notice Vault core interface.
/// Derived implementations can be effective for building tokenized vaults with single or multiple underlying liquidity mining position.
/// Fungible, static non-fungible and actively re-balancing liquidity is supported, as well as single token liquidity provided to lending protocols.
/// Vaults can be used for active concentrated liquidity management and market making.
interface IVault is IERC165 {


    //region ----- Custom Errors -----
    error IncorrectMsgSender();
    error ETHTransferFailed();
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
    event MaxSupply(uint maxShares);

    //endregion -- Events -----

    //region ----- Read functions -----

    /// @notice Immutable vault type ID
    function VAULT_TYPE() external view returns (string memory);

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
    function depositAssets(address[] memory assets_, uint[] memory amountsMax, uint minSharesOut) external;

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

    /// @dev Initialization of vault which is usually called by the Factory
    /// @param platform_ Platform provide access control, infrastructure addresses, fee settings, ability to upgrade etc
    /// @param strategy_ Immutable strategy proxy used by the vault
    /// @param name_ Vault ERC20 name
    /// @param symbol_ Vault ERC20 symbol
    /// @param tokenId_ VaultManager NFT ID
    function initialize(
        address platform_,
        address strategy_,
        string memory name_,
        string memory symbol_,
        uint tokenId_,
        address[] memory vaultInitAddresses,
        uint[] memory vaultInitNums
    ) external;

    /// @dev Calling the strategy HardWork by operator with optional compensation for spent gas from the vault balance
    function doHardWork() external;

    //endregion -- Write functions -----

}
