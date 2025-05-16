// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IStrategy} from "./IStrategy.sol";
import {IStabilityVault} from "./IStabilityVault.sol";

/// @notice Vault core interface.
/// Derived implementations can be effective for building tokenized vaults with single or multiple underlying liquidity mining position.
/// Fungible, static non-fungible and actively re-balancing liquidity is supported, as well as single token liquidity provided to lending protocols.
/// Vaults can be used for active concentrated liquidity management and market making.
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
interface IVault is IERC165, IStabilityVault {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error NotEnoughBalanceToPay();
    error FuseTrigger();
    error ExceedSlippageExactAsset(address asset, uint mintToUser, uint minToMint);
    error NotEnoughAmountToInitSupply(uint mintAmount, uint initialShares);
    error StrategyZeroDeposit();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event HardWorkGas(uint gasUsed, uint gasCost, bool compensated);
    event DoHardWorkOnDepositChanged(bool oldValue, bool newValue);
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

    /// @notice Write version of previewDepositAssets
    /// @param assets_ Assets suitable for vault strategy. Can be strategy assets, underlying asset or specific set of assets depending on strategy logic.
    /// @param amountsMax Available amounts of assets_ that user wants to invest in vault
    /// @return amountsConsumed Amounts of strategy assets that can be deposited by providing amountsMax
    /// @return sharesOut Amount of vault shares that will be minted
    /// @return valueOut Liquidity value or underlying token amount that will be received by the strategy
    function previewDepositAssetsWrite(
        address[] memory assets_,
        uint[] memory amountsMax
    ) external returns (uint[] memory amountsConsumed, uint sharesOut, uint valueOut);

    /// @dev Mint fee shares callback
    /// @param revenueAssets Assets returned by _claimRevenue function that was earned during HardWork
    /// @param revenueAmounts Assets amounts returned from _claimRevenue function that was earned during HardWork
    /// Only strategy can call this
    function hardWorkMintFeeCallback(address[] memory revenueAssets, uint[] memory revenueAmounts) external;

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
}
