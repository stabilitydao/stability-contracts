// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPriceAggregator} from "../interfaces/IPriceAggregator.sol";
import {Controllable, IControllable} from "./base/Controllable.sol";

/// @dev A contract for aggregating vault prices from multiple validators using a quorum-based median mechanism.
/// Changelog:
///   1.1.0: VaultPriceOracle => PriceAggregator - #414
///   1.0.1: review fixes
/// @author ruby (https://github.com/alexandersazonof)
/// @author Omriss (https://github.com/omriss)
contract PriceAggregator is Controllable, IPriceAggregator {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.1.0";

    /// @notice keccak256(abi.encode(uint256(keccak256("erc7201:stability.VaultPriceOracle")) - 1)) & ~bytes32(uint256(0xff));
    /// @dev Originally contract had name VaultPriceOracle, so storage wasn't renamed to PriceAggregator
    bytes32 private constant VAULT_PRICE_ORACLE_STORAGE_LOCATION =
        0xa68171b251d015e5a139782486873a18b874637da10a73c080418fb52ac37300;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.VaultPriceOracle
    /// @dev Originally contract had name VaultPriceOracle, so storage wasn't renamed to PriceAggregator
    /// @dev entity = vault | asset
    struct VaultPriceOracleStorage {
        mapping(address entity => AggregatedData) entityPrices;
        mapping(address entity => mapping(uint roundId => mapping(address validator => Observation))) observations;
        mapping(address validator => bool authorized) authorizedValidators;
        mapping(address entity => EntityData) entityData;
        address[] validators;
        /// @notice List of all registered vaults
        address[] vaults;
        /// @notice Minimum number of validator submissions required to aggregate a price
        uint minQuorum;
        /// @notice Maximum age of a price before it is considered stale (in seconds)
        uint maxPriceAge;
        /// @notice List of all registered assets
        address[] assets;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyValidator() {
        _requireValidator();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IPriceAggregator
    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
    }

    //region ------------------------------------ Restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IPriceAggregator
    function submitPrice(address entity_, uint price_, uint roundId_) external onlyValidator {
        VaultPriceOracleStorage storage $ = _getStorage();
        uint currentRoundId = $.entityPrices[entity_].roundId == 0 ? 1 : $.entityPrices[entity_].roundId;
        require(roundId_ == currentRoundId, IPriceAggregator.InvalidRoundId());

        $.observations[entity_][currentRoundId][msg.sender] = Observation({price: price_, timestamp: block.timestamp});
        emit PriceSubmitted(entity_, msg.sender, price_, currentRoundId);

        if (_countSubmissions(entity_, currentRoundId) >= $.minQuorum) {
            _aggregateAndUpdate(entity_, currentRoundId);
        }
    }

    /// @inheritdoc IPriceAggregator
    function addValidator(address validator_) external onlyGovernanceOrMultisig {
        VaultPriceOracleStorage storage $ = _getStorage();
        require(!$.authorizedValidators[validator_], IPriceAggregator.ValidatorAlreadyAuthorized());
        $.authorizedValidators[validator_] = true;
        $.validators.push(validator_);
        emit ValidatorAdded(validator_);
    }

    /// @inheritdoc IPriceAggregator
    function removeValidator(address validator_) external onlyGovernanceOrMultisig {
        VaultPriceOracleStorage storage $ = _getStorage();
        require($.authorizedValidators[validator_], IPriceAggregator.NotAuthorizedValidator());
        $.authorizedValidators[validator_] = false;
        address[] memory _validators = $.validators;
        for (uint i = 0; i < _validators.length; i++) {
            if (_validators[i] == validator_) {
                $.validators[i] = _validators[_validators.length - 1];
                $.validators.pop();
                break;
            }
        }
        emit ValidatorRemoved(validator_);
    }

    /// @inheritdoc IPriceAggregator
    function addVault(address vault_, uint priceThreshold_, uint staleness_) external onlyGovernanceOrMultisig {
        VaultPriceOracleStorage storage $ = _getStorage();
        require(vault_ != address(0), IPriceAggregator.InvalidEntityAddress());

        $.entityData[vault_] = EntityData({priceThreshold: priceThreshold_, staleness: staleness_});
        $.vaults.push(vault_);
        emit VaultAdded(vault_);
    }

    /// @inheritdoc IPriceAggregator
    function removeVault(address vault_) external onlyGovernanceOrMultisig {
        VaultPriceOracleStorage storage $ = _getStorage();
        require(vault_ != address(0), IPriceAggregator.InvalidEntityAddress());

        bool found = false;
        address[] memory _vaults = $.vaults;
        for (uint i = 0; i < _vaults.length; i++) {
            if (_vaults[i] == vault_) {
                $.vaults[i] = _vaults[_vaults.length - 1];
                $.vaults.pop();
                found = true;
                break;
            }
        }
        require(found, IPriceAggregator.EntityNotFound());
        delete $.entityData[vault_];
        emit VaultRemoved(vault_);
    }

    /// @inheritdoc IPriceAggregator
    function addAsset(address asset_, uint priceThreshold_, uint staleness_) external onlyGovernanceOrMultisig {
        VaultPriceOracleStorage storage $ = _getStorage();
        require(asset_ != address(0), IPriceAggregator.InvalidEntityAddress());

        $.entityData[asset_] = EntityData({priceThreshold: priceThreshold_, staleness: staleness_});
        $.assets.push(asset_);
        emit AssetAdded(asset_);
    }

    /// @inheritdoc IPriceAggregator
    function removeAsset(address asset_) external onlyGovernanceOrMultisig {
        VaultPriceOracleStorage storage $ = _getStorage();
        require(asset_ != address(0), IPriceAggregator.InvalidEntityAddress());

        bool found = false;
        address[] memory _assets = $.assets;
        for (uint i = 0; i < _assets.length; i++) {
            if (_assets[i] == asset_) {
                $.assets[i] = _assets[_assets.length - 1];
                $.assets.pop();
                found = true;
                break;
            }
        }
        require(found, IPriceAggregator.EntityNotFound());
        delete $.entityData[asset_];
        emit AssetRemoved(asset_);
    }

    /// @inheritdoc IPriceAggregator
    function setMinQuorum(uint minQuorum_) external onlyGovernanceOrMultisig {
        VaultPriceOracleStorage storage $ = _getStorage();
        require(minQuorum_ != 0, IPriceAggregator.MinQuorumMustBeGreaterThanZero());
        $.minQuorum = minQuorum_;
    }

    /// @inheritdoc IPriceAggregator
    function setMaxPriceAge(uint maxPriceAge_) external onlyGovernanceOrMultisig {
        VaultPriceOracleStorage storage $ = _getStorage();
        require(maxPriceAge_ > 0, IPriceAggregator.MaxPriceAgeMustBeGreaterThanZero());
        $.maxPriceAge = maxPriceAge_;
    }

    //endregion ------------------------------------ Restricted actions

    //region ------------------------------------ View
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IPriceAggregator
    function getLatestPrice(address entity_) external view returns (uint _price, uint timestamp, uint roundId) {
        VaultPriceOracleStorage storage $ = _getStorage();
        AggregatedData memory data = $.entityPrices[entity_];
        require(data.timestamp > 0, IPriceAggregator.NoDataAvailable());
        require(block.timestamp <= data.timestamp + $.maxPriceAge, IPriceAggregator.PriceTooOld());
        return (data.price, data.timestamp, data.roundId);
    }

    /// @inheritdoc IPriceAggregator
    function price(address entity_) external view returns (uint _price, uint timestamp, uint roundId) {
        VaultPriceOracleStorage storage $ = _getStorage();
        AggregatedData memory data = $.entityPrices[entity_];
        return (data.price, data.timestamp, data.roundId);
    }

    /// @inheritdoc IPriceAggregator
    function observations(
        address entity_,
        uint roundId_,
        address validator_
    ) external view returns (uint _price, uint timestamp) {
        VaultPriceOracleStorage storage $ = _getStorage();
        Observation memory data = $.observations[entity_][roundId_][validator_];
        return (data.price, data.timestamp);
    }

    /// @inheritdoc IPriceAggregator
    function authorizedValidator(address validator_) external view returns (bool) {
        VaultPriceOracleStorage storage $ = _getStorage();
        return $.authorizedValidators[validator_];
    }

    /// @inheritdoc IPriceAggregator
    function vaultByIndex(uint index_) external view returns (address) {
        VaultPriceOracleStorage storage $ = _getStorage();
        require(index_ < $.vaults.length, IPriceAggregator.IndexOutOfBounds());
        return $.vaults[index_];
    }

    /// @inheritdoc IPriceAggregator
    function vaults() external view returns (address[] memory) {
        VaultPriceOracleStorage storage $ = _getStorage();
        return $.vaults;
    }

    /// @inheritdoc IPriceAggregator
    function vaultsLength() external view returns (uint) {
        VaultPriceOracleStorage storage $ = _getStorage();
        return $.vaults.length;
    }

    /// @inheritdoc IPriceAggregator
    function assetByIndex(uint index_) external view returns (address) {
        VaultPriceOracleStorage storage $ = _getStorage();
        require(index_ < $.assets.length, IPriceAggregator.IndexOutOfBounds());
        return $.assets[index_];
    }

    /// @inheritdoc IPriceAggregator
    function assets() external view returns (address[] memory) {
        VaultPriceOracleStorage storage $ = _getStorage();
        return $.assets;
    }

    /// @inheritdoc IPriceAggregator
    function assetsLength() external view returns (uint) {
        VaultPriceOracleStorage storage $ = _getStorage();
        return $.assets.length;
    }

    /// @inheritdoc IPriceAggregator
    function validatorByIndex(uint index_) external view returns (address) {
        VaultPriceOracleStorage storage $ = _getStorage();
        require(index_ < $.validators.length, IPriceAggregator.IndexOutOfBounds());
        return $.validators[index_];
    }

    /// @inheritdoc IPriceAggregator
    function validators() external view returns (address[] memory) {
        VaultPriceOracleStorage storage $ = _getStorage();
        return $.validators;
    }

    /// @inheritdoc IPriceAggregator
    function validatorsLength() external view returns (uint) {
        VaultPriceOracleStorage storage $ = _getStorage();
        return $.validators.length;
    }

    /// @inheritdoc IPriceAggregator
    function minQuorum() external view returns (uint) {
        VaultPriceOracleStorage storage $ = _getStorage();
        return $.minQuorum;
    }

    /// @inheritdoc IPriceAggregator
    function maxPriceAge() external view returns (uint) {
        VaultPriceOracleStorage storage $ = _getStorage();
        return $.maxPriceAge;
    }

    /// @inheritdoc IPriceAggregator
    function entityData(address entity_) external view returns (uint priceThreshold, uint staleness) {
        VaultPriceOracleStorage storage $ = _getStorage();
        EntityData memory data = $.entityData[entity_];
        return (data.priceThreshold, data.staleness);
    }

    //endregion ------------------------------------ View

    //region ------------------------------------ Internal logic
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Counts the number of valid price submissions for a vault in a specific round.
    /// @dev Iterates through the list of validators to check if they have submitted a price (non-zero timestamp).
    /// @param entity_ The address of the vault or asset to check submissions for.
    /// @param roundId_ The ID of the round to count submissions for.
    /// @return count The number of valid submissions in the specified round.
    function _countSubmissions(address entity_, uint roundId_) internal view returns (uint) {
        VaultPriceOracleStorage storage $ = _getStorage();
        uint count;
        address[] memory _validators = $.validators;
        for (uint i; i < _validators.length; i++) {
            if ($.observations[entity_][roundId_][_validators[i]].timestamp != 0) {
                count++;
            }
        }
        return count;
    }

    /// @notice Aggregates submitted prices for an entity (vault or asset) in a specific round and updates the entity's price data.
    /// @dev Collects valid prices from validators, computes the median, and updates the entity's aggregated data.
    ///      Emits a PriceUpdated event upon successful aggregation.
    /// @param entity_ The address of the vault or asset to aggregate prices for.
    /// @param roundId_ The ID of the round to aggregate.
    function _aggregateAndUpdate(address entity_, uint roundId_) internal {
        VaultPriceOracleStorage storage $ = _getStorage();
        address[] memory _validators = $.validators;
        mapping(address => Observation) storage _observations = $.observations[entity_][roundId_];

        uint validCount;
        for (uint i; i < _validators.length; i++) {
            if (_observations[_validators[i]].timestamp > 0) {
                validCount++;
            }
        }

        uint[] memory prices = new uint[](validCount);
        uint idx;
        for (uint i; i < _validators.length; i++) {
            Observation storage obs = _observations[_validators[i]];
            if (obs.timestamp > 0) {
                prices[idx] = obs.price;
                idx++;
            }
        }

        uint medianPrice = _getMedian(prices);

        uint newRoundId = roundId_ + 1;
        $.entityPrices[entity_] = AggregatedData({price: medianPrice, timestamp: block.timestamp, roundId: newRoundId});
        emit PriceUpdated(entity_, medianPrice, roundId_, block.timestamp);
    }

    /// @notice Calculates the median value from a list of prices.
    /// @dev Sorts the array using quicksort and returns the median.
    ///      For even counts, returns the average of the two middle values; for odd counts, returns the middle value.
    /// @param prices_ The array containing valid prices.
    /// @return The median price, or 0 if no valid prices are provided.
    function _getMedian(uint[] memory prices_) internal pure returns (uint) {
        uint count = prices_.length;
        if (count == 0) return 0;
        _quickSort(prices_, 0, count - 1);
        if (count % 2 == 0) {
            return (prices_[count / 2 - 1] + prices_[count / 2]) / 2;
        } else {
            return prices_[count / 2];
        }
    }

    /// @notice Sorts an array of prices using the quicksort algorithm.
    /// @dev Recursively sorts the array by selecting a pivot and partitioning around it.
    /// @param arr_ The array to sort.
    /// @param low_ The starting index of the subarray to sort.
    /// @param high_ The ending index of the subarray to sort.
    function _quickSort(uint[] memory arr_, uint low_, uint high_) internal pure {
        if (low_ < high_) {
            uint pi = _partition(arr_, low_, high_);
            if (pi > 0) {
                _quickSort(arr_, low_, pi - 1);
            }
            _quickSort(arr_, pi + 1, high_);
        }
    }

    /// @notice Partitions an array around a pivot for quicksort.
    /// @dev Selects the last element as the pivot and rearranges elements so that smaller ones are on the left.
    /// @param arr_ The array to partition.
    /// @param low_ The starting index of the subarray.
    /// @param high_ The ending index of the subarray (pivot location).
    /// @return The index of the pivot after partitioning.
    function _partition(uint[] memory arr_, uint low_, uint high_) internal pure returns (uint) {
        uint pivot = arr_[high_];
        uint i = low_;

        for (uint j = low_; j < high_; j++) {
            if (arr_[j] <= pivot) {
                (arr_[i], arr_[j]) = (arr_[j], arr_[i]);
                i++;
            }
        }
        (arr_[i], arr_[high_]) = (arr_[high_], arr_[i]);
        return i;
    }

    function _getStorage() private pure returns (VaultPriceOracleStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := VAULT_PRICE_ORACLE_STORAGE_LOCATION
        }
    }

    function _requireValidator() internal view {
        VaultPriceOracleStorage storage $ = _getStorage();
        require($.authorizedValidators[msg.sender], IPriceAggregator.NotAuthorizedValidator());
    }
    //endregion ------------------------------------ Internal logic
}
