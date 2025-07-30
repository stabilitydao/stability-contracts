// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Oracle Vault Price Interface
/// @author ruby (https://github.com/alexandersazonof)
/// @notice Interface for the VaultPriceOracle contract, which aggregates prices from multiple oracles for vaults using a quorum-based median mechanism.
interface IVaultPriceOracle {

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Structure representing a single price observation from an oracle.
    /// @dev Contains the submitted price and the timestamp of submission.
    struct Observation {
        uint256 price;
        uint256 timestamp;
    }

    /// @notice Structure representing aggregated price data for a vault.
    /// @dev Includes the median price, aggregation timestamp, and associated round ID.
    struct AggregatedData {
        uint256 price;
        uint256 timestamp;
        uint256 roundId;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when an oracle submits a price for a vault in a specific round.
    /// @param vault The address of the vault.
    /// @param oracle The address of the oracle submitting the price.
    /// @param price The submitted price.
    /// @param roundId The ID of the round for this submission.
    event PriceSubmitted(address indexed vault, address indexed oracle, uint256 price, uint256 roundId);

    /// @notice Emitted when the price for a vault is updated after aggregation.
    /// @param vault The address of the vault.
    /// @param price The aggregated median price.
    /// @param roundId The ID of the round that was aggregated.
    /// @param timestamp The timestamp of the aggregation.
    event PriceUpdated(address indexed vault, uint256 price, uint256 roundId, uint256 timestamp);

    /// @notice Emitted when a new validator is added.
    /// @param validator The address of the added validator.
    event ValidatorAdded(address indexed validator);

    /// @notice Emitted when a validator is removed.
    /// @param validator The address of the removed validator.
    event ValidatorRemoved(address indexed validator);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Retrieves the aggregated price data for a specific vault.
    /// @param vault The address of the vault.
    /// @return price The aggregated median price.
    /// @return timestamp The timestamp of the aggregation.
    /// @return roundId The ID of the aggregated round.
    function vaultPrices(address vault) external view returns (uint256 price, uint256 timestamp, uint256 roundId);

    /// @notice Retrieves a specific observation for a vault, round, and oracle.
    /// @param vault The address of the vault.
    /// @param roundId The ID of the round.
    /// @param validator The address of the validator.
    /// @return price The submitted price.
    /// @return timestamp The submission timestamp.
    function observations(address vault, uint256 roundId, address validator) external view returns (uint256 price, uint256 timestamp);

    /// @notice Checks if an address is an authorized validator.
    /// @param validator The address to check.
    /// @return True if authorized, false otherwise.
    function authorizedValidator(address validator) external view returns (bool);

    /// @notice Retrieves an validator address from the list by index.
    /// @param index The index in the oracle list.
    /// @return The address of the validator at that index.
    function validatorList(uint256 index) external view returns (address);

    /// @notice Returns the minimum quorum required for aggregation.
    /// @return The minimum number of submissions needed.
    function minQuorum() external view returns (uint256);

    /// @notice Returns the maximum age allowed for a price before it's considered stale.
    /// @return The maximum age in seconds.
    function maxPriceAge() external view returns (uint256);

    /// @notice Retrieves the latest valid aggregated price for a vault.
    /// @dev Reverts if no data is available or if the price is too old.
    /// @param _vault The address of the vault.
    /// @return price The latest aggregated price.
    /// @return timestamp The aggregation timestamp.
    /// @return roundId The associated round ID.
    function getLatestPrice(address _vault) external view returns (uint256 price, uint256 timestamp, uint256 roundId);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(address platform_, uint256 _minQuorum, address[] memory _validator, uint256 _maxPriceAge) external;

    /// @notice Submits a price for a vault in the current round.
    /// @dev Can only be called by authorized validators.
    /// @param _vault The address of the vault.
    /// @param _price The price to submit.
    /// @param _roundId The ID of the round (must match current).
    function submitPrice(address _vault, uint256 _price, uint256 _roundId) external;

    /// @notice Adds a new validator to the authorized list.
    /// @dev Restricted to governance or multisig.
    /// @param _validator The address of the validator to add.
    function addValidator(address _validator) external;

    /// @notice Removes an validator from the authorized list.
    /// @dev Restricted to governance or multisig.
    /// @param _validator The address of the validator to remove.
    function removeValidator(address _validator) external;
}