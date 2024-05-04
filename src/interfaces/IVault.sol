// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./IStrategy.sol";

/// @notice Vault core interface.
/// Derived implementations can be effective for building tokenized vaults with single or multiple underlying liquidity mining position.
/// Fungible, static non-fungible and actively re-balancing liquidity is supported, as well as single token liquidity provided to lending protocols.
/// Vaults can be used for active concentrated liquidity management and market making.
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
interface IVault is IERC165 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error NotEnoughBalanceToPay();
    error FuseTrigger();
    error ExceedSlippage(uint mintToUser, uint minToMint);
    error ExceedSlippageExactAsset(address asset, uint mintToUser, uint minToMint);
    error ExceedMaxSupply(uint maxSupply);
    error NotEnoughAmountToInitSupply(uint mintAmount, uint initialShares);
    error WaitAFewBlocks();
    error StrategyZeroDeposit();
    error NotSupported();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event DepositAssets(address indexed account, address[] assets, uint[] amounts, uint mintAmount);
    event WithdrawAssets(
        address indexed sender, address indexed owner, address[] assets, uint sharesAmount, uint[] amountsOut
    );
    event HardWorkGas(uint gasUsed, uint gasCost, bool compensated);
    event DoHardWorkOnDepositChanged(bool oldValue, bool newValue);
    event MaxSupply(uint maxShares);
    event VaultName(string newName);
    event VaultSymbol(string newSymbol);
    event MintFees(
        uint vaultManagerReceiverFee,
        uint strategyLogicReceiverFee,
        uint ecosystemRevenueReceiverFee,
        uint multisigReceiverFee
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.VaultBase
    struct VaultBaseStorage {
        /// @dev Prevents manipulations with deposit and withdraw in short time.
        ///      For simplification we are setup new withdraw request on each deposit/transfer.
        mapping(address msgSender => uint blockNumber) withdrawRequests;
        /// @inheritdoc IVault
        IStrategy strategy;
        /// @inheritdoc IVault
        uint maxSupply;
        /// @inheritdoc IVault
        uint tokenId;
        /// @inheritdoc IVault
        bool doHardWorkOnDeposit;
        /// @dev Immutable vault type ID
        string _type;
        /// @dev Changed ERC20 name
        string changedName;
        /// @dev Changed ERC20 symbol
        string changedSymbol;
    }

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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Immutable vault type ID
    function vaultType() external view returns (string memory);

    /// @return uniqueInitAddresses Return required unique init addresses
    /// @return uniqueInitNums Return required unique init nums
    function getUniqueInitParamLength() external view returns (uint uniqueInitAddresses, uint uniqueInitNums);

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
    function doHardWorkOnDeposit() external view returns (bool);

    /// @dev USD price of share with 18 decimals.
    ///      ONLY FOR OFF-CHAIN USE.
    ///      Not trusted vault share price can be manipulated.
    /// @return price_ Price of 1e18 shares with 18 decimals precision
    /// @return trusted True means oracle price, false means AMM spot price
    function price() external view returns (uint price_, bool trusted);

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
    function previewDepositAssets(
        address[] memory assets_,
        uint[] memory amountsMax
    ) external view returns (uint[] memory amountsConsumed, uint sharesOut, uint valueOut);

    /// @notice All available data on the latest declared APR (annual percentage rate)
    /// @return totalApr Total APR of investing money to vault. 18 decimals: 1e18 - +100% per year.
    /// @return strategyApr Strategy investmnt APR declared on last HardWork.
    /// @return assetsWithApr Assets with underlying APR
    /// @return assetsAprs Underlying APR of asset
    function getApr()
        external
        view
        returns (uint totalApr, uint strategyApr, address[] memory assetsWithApr, uint[] memory assetsAprs);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Mint fee shares callback
    /// @param revenueAssets Assets returned by _claimRevenue function that was earned during HardWork
    /// @param revenueAmounts Assets amounts returned from _claimRevenue function that was earned during HardWork
    /// Only strategy can call this
    function hardWorkMintFeeCallback(address[] memory revenueAssets, uint[] memory revenueAmounts) external;

    /// @dev Deposit final assets (pool assets) to the strategy and minting of vault shares.
    ///      If the strategy interacts with a pool or farms through an underlying token, then it will be minted.
    ///      Emits a {DepositAssets} event with consumed amounts.
    /// @param assets_ Assets suitable for the strategy. Can be strategy assets, underlying asset or specific set of assets depending on strategy logic.
    /// @param amountsMax Available amounts of assets_ that user wants to invest in vault
    /// @param minSharesOut Slippage tolerance. Minimal shares amount which must be received by user.
    /// @param receiver Receiver of deposit. If receiver is zero address, receiver is msg.sender.
    function depositAssets(
        address[] memory assets_,
        uint[] memory amountsMax,
        uint minSharesOut,
        address receiver
    ) external;

    /// @dev Burning shares of vault and obtaining strategy assets.
    /// @param assets_ Assets suitable for the strategy. Can be strategy assets, underlying asset or specific set of assets depending on strategy logic.
    /// @param amountShares Shares amount for burning
    /// @param minAssetAmountsOut Slippage tolerance. Minimal amounts of strategy assets that user must receive.
    /// @return Amount of assets for withdraw. It's related to assets_ one-by-one.
    function withdrawAssets(
        address[] memory assets_,
        uint amountShares,
        uint[] memory minAssetAmountsOut
    ) external returns (uint[] memory);

    /// @dev Burning shares of vault and obtaining strategy assets.
    /// @param assets_ Assets suitable for the strategy. Can be strategy assets, underlying asset or specific set of assets depending on strategy logic.
    /// @param amountShares Shares amount for burning
    /// @param minAssetAmountsOut Slippage tolerance. Minimal amounts of strategy assets that user must receive.
    /// @param receiver Receiver of assets
    /// @param owner Owner of vault shares
    /// @return Amount of assets for withdraw. It's related to assets_ one-by-one.
    function withdrawAssets(
        address[] memory assets_,
        uint amountShares,
        uint[] memory minAssetAmountsOut,
        address receiver,
        address owner
    ) external returns (uint[] memory);

    /// @dev Setting of vault capacity
    /// @param maxShares If totalSupply() exceeds this value, deposits will not be possible
    function setMaxSupply(uint maxShares) external;

    /// @dev If activated will call doHardWork on strategy on some deposit actions
    /// @param value HardWork on deposit is enabled
    function setDoHardWorkOnDeposit(bool value) external;

    /// @notice Initialization function for the vault.
    /// @dev This function is usually called by the Factory during the creation of a new vault.
    /// @param vaultInitializationData Data structure containing parameters for vault initialization.
    function initialize(VaultInitializationData memory vaultInitializationData) external;

    /// @dev Calling the strategy HardWork by operator with optional compensation for spent gas from the vault balance
    function doHardWork() external;

    /// @dev Changing ERC20 name of vault
    function setName(string calldata newName) external;

    /// @dev Changing ERC20 symbol of vault
    function setSymbol(string calldata newSymbol) external;
}
