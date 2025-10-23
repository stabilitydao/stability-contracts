// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Oracle Vault Price Interface
/// @author ruby (https://github.com/alexandersazonof)
/// @notice Interface for the VaultPriceOracle contract, which aggregates prices from multiple oracles for vaults using a quorum-based median mechanism.
/// @dev original IVaultPriceOracle was renamed to IPriceAggregator
interface IPriceAggregator {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error InvalidRoundId();
    error ValidatorAlreadyAuthorized();
    error InvalidEntityAddress();
    error MinQuorumMustBeGreaterThanZero();
    error MaxPriceAgeMustBeGreaterThanZero();
    error NoDataAvailable();
    error PriceTooOld();
    error IndexOutOfBounds();
    error NotAuthorizedValidator();
    error EntityNotFound();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Structure representing a single price observation from an oracle.
    /// @dev Contains the submitted price and the timestamp of submission.
    struct Observation {
        uint price;
        uint timestamp;
    }

    /// @notice Structure representing aggregated price data for a vault.
    /// @dev Includes the median price, aggregation timestamp, and associated round ID.
    struct AggregatedData {
        uint price;
        uint timestamp;
        uint roundId;
    }

    /// @notice Structure representing the data for a vault/asset in the oracle.
    /// @dev Contains the price threshold and staleness period for the vault.
    struct EntityData {
        /// @notice Percentage change when the price should be updated, in basis points (e.g., 100 = 0.1%)
        uint priceThreshold;
        /// @notice Maximum age of price before considered stale, in seconds
        uint staleness;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when an oracle submits a price for a entity in a specific round.
    /// @param entity The address of the vault or asset.
    /// @param oracle The address of the oracle submitting the price.
    /// @param price The submitted price.
    /// @param roundId The ID of the round for this submission.
    event PriceSubmitted(address indexed entity, address indexed oracle, uint price, uint roundId);

    /// @notice Emitted when the price for a entity is updated after aggregation.
    /// @param entity The address of the vault or asset.
    /// @param price The aggregated median price.
    /// @param roundId The ID of the round that was aggregated.
    /// @param timestamp The timestamp of the aggregation.
    event PriceUpdated(address indexed entity, uint price, uint roundId, uint timestamp);

    /// @notice Emitted when a new validator is added.
    /// @param validator The address of the added validator.
    event ValidatorAdded(address indexed validator);

    /// @notice Emitted when a validator is removed.
    /// @param validator The address of the removed validator.
    event ValidatorRemoved(address indexed validator);

    /// @notice Emitted when vault is added to the oracle.
    /// @param vault The address of the added vault.
    event VaultAdded(address indexed vault);

    /// @notice Emitted when vault is removed from the oracle.
    /// @param vault The address of the removed vault.
    event VaultRemoved(address indexed vault);

    /// @notice Emitted when asset is added to the oracle.
    /// @param asset The address of the added asset.
    event AssetAdded(address indexed asset);

    /// @notice Emitted when asset is removed from the oracle.
    /// @param asset The address of the removed asset.
    event AssetRemoved(address indexed asset);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Retrieves the aggregated price data for a specific vault or asset.
    /// @param entity_ The address of the vault.
    /// @return _price The aggregated median price.
    /// @return timestamp The timestamp of the aggregation.
    /// @return roundId The ID of the aggregated round.
    function price(address entity_) external view returns (uint _price, uint timestamp, uint roundId);

    /// @notice Retrieves a specific observation for a vault | asset, round, and oracle.
    /// @param entity_ The address of the vault or asset.
    /// @param roundId_ The ID of the round.
    /// @param validator_ The address of the validator.
    /// @return _price The submitted price.
    /// @return timestamp The submission timestamp.
    function observations(
        address entity_,
        uint roundId_,
        address validator_
    ) external view returns (uint _price, uint timestamp);

    /// @notice Checks if an address is an authorized validator.
    /// @param validator_ The address to check.
    /// @return True if authorized, false otherwise.
    function authorizedValidator(address validator_) external view returns (bool);

    /// @notice Retrieves an validator address from the list by index.
    /// @param index_ The index in the oracle list.
    /// @return The address of the validator at that index.
    function validatorByIndex(uint index_) external view returns (address);

    /// @notice Retrieves the list of all authorized validators.
    /// @return An array of addresses representing the validators.
    function validators() external view returns (address[] memory);

    /// @notice Retrieves the number of validators.
    function validatorsLength() external view returns (uint);

    /// @notice Retrieves a vault address from the list by index.
    /// @param index_ The index in the vault list.
    function vaultByIndex(uint index_) external view returns (address);

    /// @notice Returns the list of all vaults being monitored by this oracle.
    /// @return An array of addresses representing the vaults.
    function vaults() external view returns (address[] memory);

    /// @notice Returns the number of vaults being monitored by this oracle.
    function vaultsLength() external view returns (uint);

    /// @notice Retrieves an asset address from the list by index.
    /// @param index_ The index in the assets list.
    function assetByIndex(uint index_) external view returns (address);

    /// @notice Returns the list of all assets being monitored by this oracle.
    /// @return An array of addresses representing the assets.
    function assets() external view returns (address[] memory);

    /// @notice Returns the number of assets being monitored by this oracle.
    function assetsLength() external view returns (uint);

    /// @notice Returns the minimum quorum required for aggregation.
    /// @return The minimum number of submissions needed.
    function minQuorum() external view returns (uint);

    /// @notice Returns the maximum age allowed for a price before it's considered stale.
    /// @return The maximum age in seconds.
    function maxPriceAge() external view returns (uint);

    /// @notice Retrieves the latest valid aggregated price for a vault or asset.
    /// @dev Reverts if no data is available or if the price is too old.
    /// @param entity_ The address of the entity.
    /// @return price The latest aggregated price.
    /// @return timestamp The aggregation timestamp.
    /// @return roundId The associated round ID.
    function getLatestPrice(address entity_) external view returns (uint price, uint timestamp, uint roundId);

    /// @notice Retrieves the price threshold and staleness for a specific vault or asset.
    /// @param entity_ The address of the vault or asset.
    /// @return priceThreshold The price threshold for the vault.
    /// @return staleness The staleness period for the vault.
    function entityData(address entity_) external view returns (uint priceThreshold, uint staleness);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Submits a price for a vault/asset in the current round.
    /// @dev Can only be called by authorized validators.
    /// @param entity_ The address of the vault or asset.
    /// @param price_ The price to submit.
    /// @param roundId_ The ID of the round (must match current), starting from 1 and incrementing by 1 each round.
    function submitPrice(address entity_, uint price_, uint roundId_) external;

    /// @notice Adds a new validator to the authorized list.
    /// @dev Restricted to governance or multisig.
    /// @param validator_ The address of the validator to add.
    function addValidator(address validator_) external;

    /// @notice Removes an validator from the authorized list.
    /// @dev Restricted to governance or multisig.
    /// @param validator_ The address of the validator to remove.
    function removeValidator(address validator_) external;

    /// @notice Sets the minimum quorum required for aggregation.
    /// @dev Restricted to governance or multisig.
    function setMinQuorum(uint minQuorum_) external;

    /// @notice Sets the maximum age allowed for a price before it's considered stale.
    /// @dev Restricted to governance or multisig.
    function setMaxPriceAge(uint maxPriceAge_) external;

    /// @notice Adds a new vault to be monitored by the oracle.
    /// @dev Restricted to governance or multisig.
    /// @param vault_ The address of the vault to add.
    /// @param priceThreshold_ The price threshold for the vault.
    /// @param staleness_ The staleness period for the vault.
    function addVault(address vault_, uint priceThreshold_, uint staleness_) external;

    /// @notice Removes a vault from being monitored by the oracle.
    /// @dev Restricted to governance or multisig.
    /// @param vault_ The address of the vault to remove.
    function removeVault(address vault_) external;

    /// @notice Adds a new asset to be monitored by the oracle.
    /// @dev Restricted to governance or multisig.
    /// @param asset_ The address of the vault to add.
    /// @param priceThreshold_ The price threshold for the asset.
    /// @param staleness_ The staleness period for the asset.
    function addAsset(address asset_, uint priceThreshold_, uint staleness_) external;

    /// @notice Removes an asset from being monitored by the oracle.
    /// @dev Restricted to governance or multisig.
    /// @param asset_ The address of the asset to remove.
    function removeAsset(address asset_) external;
}
