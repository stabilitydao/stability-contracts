// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IStabilityVault} from "./IStabilityVault.sol";

interface IMetaVault is IStabilityVault {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.MetaVault
    struct MetaVaultStorage {
        /// @dev Flash loan exploit protection.
        ///      Prevents manipulations with deposit/transfer and withdraw/deposit in short time.
        mapping(address msgSender => uint blockNumber) lastTransferBlock;
        /// @dev Immutable vault type ID
        string _type;
        /// @inheritdoc IMetaVault
        address pegAsset;
        /// @inheritdoc IMetaVault
        EnumerableSet.AddressSet assets;
        /// @inheritdoc IMetaVault
        address[] vaults;
        /// @inheritdoc IMetaVault
        uint[] targetProportions;
        /// @inheritdoc IERC20Metadata
        string name;
        /// @inheritdoc IERC20Metadata
        string symbol;
        /// @inheritdoc IERC20
        mapping(address owner => mapping(address spender => uint allowance)) allowance;
        /// @dev Total internal shares
        uint totalShares;
        /// @dev Internal user balances
        mapping(address => uint) shareBalance;
        /// @dev Stored share price to track MetaVault APR
        uint storedSharePrice;
        /// @dev Last time APR emitted
        uint storedTime;
        /// @inheritdoc IStabilityVault
        bool lastBlockDefenseDisabled;
        /// @dev Whitelist for addresses (strategies) that are able to temporarily disable last-block-defense
        mapping(address owner => bool whitelisted) lastBlockDefenseWhitelist;
        /// @dev Recovery tokens for broken c-vaults
        mapping(address cVault => address recoveryToken) recoveryTokens;
        /// @notice Manager allowed to edit sub-vaults and proportions
        address vaultManager;
    }

    /// @notice Types of last-block-defense disable modes
    enum LastBlockDefenseDisableMode {
        /// @notice Last-block-defense is enabled
        ENABLED_0,
        /// @notice Last-block-defense is disabled for the current tx, update and _beforeDepositOrWithdraw update maps
        DISABLED_TX_UPDATE_MAPS_1,
        /// @notice Last-block-defense is disabled for the current tx, do not update maps
        DISABLE_TX_DONT_UPDATE_MAPS_2
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event APR(uint sharePrice, int apr, uint lastStoredSharePrice, uint duration, uint tvl);
    event Rebalance(uint[] withdrawShares, uint[] depositAmountsProportions, int cost);
    event AddVault(address vault);
    event TargetProportions(uint[] proportions);
    event WhitelistChanged(address owner, bool whitelisted);
    event RemoveVault(address vault);
    event SetVaultManager(address newManager);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error UsdAmountLessThreshold(uint amountUsd, uint threshold);
    error MaxAmountForWithdrawPerTxReached(uint amount, uint maxAmount);
    error ZeroSharesToBurn(uint amountToWithdraw);
    error IncorrectProportions();
    error IncorrectRebalanceArgs();
    error IncorrectVault();
    error NotWhitelisted();
    error VaultNotFound(address vault);
    error TooHighAmount(uint amount, uint maxAmount);
    error RecoveryTokenNotSet(address cVault_);

    //region --------------------------------------- View functions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Not perform operations with value less than threshold
    function USD_THRESHOLD() external view returns (uint);

    /// @notice Vault price pegged currency
    function pegAsset() external view returns (address);

    /// @notice Used CVaults
    function vaults() external view returns (address[] memory);

    /// @notice Current proportions of value between vaults
    /// @return Shares of 1e18
    function currentProportions() external view returns (uint[] memory);

    /// @notice Target proportions of value between vaults
    /// @return Shares of 1e18
    function targetProportions() external view returns (uint[] memory);

    /// @notice Vault where to deposit first
    function vaultForDeposit() external view returns (address);

    /// @notice Assets for deposit
    function assetsForDeposit() external view returns (address[] memory);

    /// @notice Vault for withdraw first
    function vaultForWithdraw() external view returns (address);

    /// @notice Assets for withdraw
    function assetsForWithdraw() external view returns (address[] memory);

    /// @notice Maximum withdraw amount for next withdraw TX
    function maxWithdrawAmountTx() external view returns (uint);

    /// @notice Show internal share prices
    /// @return sharePrice Current internal share price
    /// @return apr Current APR
    /// @return storedSharePrice Stored internal share price
    /// @return storedTime Time when stored
    function internalSharePrice()
        external
        view
        returns (uint sharePrice, int apr, uint storedSharePrice, uint storedTime);

    /// @notice True if the {addr} is in last-block-defense whitelist
    function whitelisted(address addr) external view returns (bool);

    /// @param cVault_ Address of the target cVault from which underlying will be withdrawn.
    /// @param account Address of the account for which the maximum withdraw amount is calculated.
    /// @return amount Maximum amount that can be withdrawn from the vault for the given account.
    /// This is max amount that can be passed to `withdraw` function.
    function maxWithdrawUnderlying(address cVault_, address account) external view returns (uint amount);

    /// @notice Recovery token for the given cVault. Zero for not-broken vaults
    function recoveryToken(address cVault_) external view returns (address);

    /// @notice Address allowed to manage vaults and proportions
    /// If 0 then multisig is the manager
    function vaultManager() external view returns (address);
    //endregion --------------------------------------- View functions

    //region --------------------------------------- Write functions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Update stored internal share price and emit APR
    /// @return sharePrice Current internal share price
    /// @return apr APR for last period
    /// @return lastStoredSharePrice Last stored internal share price
    /// @return duration Duration of last tracked period
    function emitAPR() external returns (uint sharePrice, int apr, uint lastStoredSharePrice, uint duration);

    /// @notice MetaVault re-balancing
    /// @param withdrawShares Shares to withdraw from vaults
    /// @param depositAmountsProportions Proportions to deposit
    /// @return proportions Result proportions
    /// @return cost Re-balance cost in USD
    function rebalance(
        uint[] memory withdrawShares,
        uint[] memory depositAmountsProportions
    ) external returns (uint[] memory proportions, int cost);

    /// @notice Set new target proportions
    function setTargetProportions(uint[] memory newTargetProportions) external;

    /// @notice Add CVault to MetaVault
    function addVault(address vault, uint[] memory newTargetProportions) external;

    /// @notice Remove CVault from MetaVault
    /// @dev The proportions of the vault should be zero, total deposited amount should be less then threshold
    function removeVault(address vault) external;

    /// @notice Init after deploy
    function initialize(
        address platform_,
        string memory type_,
        address pegAsset_,
        string memory name_,
        string memory symbol_,
        address[] memory vaults_,
        uint[] memory proportions_
    ) external;

    /// @notice Add/remove {addr} to/from last-block-defense whitelist
    function changeWhitelist(address addr, bool addToWhitelist) external;

    /// @notice Allow whitelisted address to disable last-block-defense for the current block or enable it back
    /// @param disableMode See {LastBlockDefenseDisableMode}
    /// 0 - the defence enabled
    /// 1 - the defence disabled in tx, maps are updated
    function setLastBlockDefenseDisabledTx(uint disableMode) external;

    /// @notice Allow to cache assets and vaults prices in the transient cache
    /// @param clear True - clear the cache, false - prepare the cache
    function cachePrices(bool clear) external;

    /// @notice Withdraw underlying from the given cVault
    /// @param cVault_ Address of the target cVault from which underlying will be withdrawn.
    /// The cVault can belong to the MetaVault directly or belong to one of its sub-meta-vaults.
    /// @param amount Amount of meta-vault tokens to be withdrawn
    /// @param minUnderlyingOut Minimum amount of underlying to be received
    /// @param receiver Address to receive underlying
    /// @param owner Address of the owner of the meta-vault tokens
    /// @return underlyingOut Amount of underlying received
    function withdrawUnderlying(
        address cVault_,
        uint amount,
        uint minUnderlyingOut,
        address receiver,
        address owner
    ) external returns (uint underlyingOut);

    /// @notice Withdraw underlying from the broken cVaults, mint recovery tokens if the caller is not whitelisted
    /// @custom:access Governance, multisig or whitelisted addresses (i.e. wrapped meta-vaults)
    /// @param cVault_ Address of the target cVault from which underlying will be withdrawn.
    /// @param owners Addresses of the owners of the meta-vault tokens
    /// @param amounts Amounts of meta-vault tokens to be withdrawn for each owner (0 - withdraw all)
    /// @param minUnderlyingOut Minimum amount of underlying to be received for each owner
    /// @param pausedRecoveryTokens If true, the recovery token will be set on puase for the given owner after minting
    /// @return amountOut Amounts of underlying received for each owner.
    /// @return recoveryAmountOut Amounts of recovery tokens received for each owner.
    function withdrawUnderlyingEmergency(
        address cVault_,
        address[] memory owners,
        uint[] memory amounts,
        uint[] memory minUnderlyingOut,
        bool[] memory pausedRecoveryTokens
    ) external returns (uint[] memory amountOut, uint[] memory recoveryAmountOut);

    /// @notice Set recovery token address for the given cVault
    /// @custom:access Governance, multisig
    function setRecoveryToken(address cVault_, address recoveryToken_) external;

    /// @notice Set new vault manager address
    /// @custom:access Governance, multisig
    function setVaultManager(address newManager) external;
    //endregion --------------------------------------- Write functions
}
