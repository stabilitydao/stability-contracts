// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IVaultPriceOracle} from "../interfaces/IVaultPriceOracle.sol";
import {Controllable, IControllable} from "./base/Controllable.sol";

/// @author ruby (https://github.com/alexandersazonof)
/// @dev A contract for aggregating vault prices from multiple validators using a quorum-based median mechanism.
contract VaultPriceOracle is Controllable, IVaultPriceOracle {

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.VaultPriceOracle")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant VAULT_PRICE_ORACLE_STORAGE_LOCATION =
    0xa68171b251d015e5a139782486873a18b874637da10a73c080418fb52ac37300;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.VaultPriceOracle
    struct VaultPriceOracleStorage {
        mapping(address => AggregatedData) vaultPrices;
        mapping(address => mapping(uint256 => mapping(address => Observation))) observations;
        mapping(address validator => bool authorized) authorizedValidators;
        address[] validatorList;
        uint256 minQuorum;
        uint256 maxPriceAge;
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

    /// @inheritdoc IVaultPriceOracle
    function initialize(address platform_, uint256 minQuorum_, address[] memory validators_, uint256 maxPriceAge_) public initializer {
        VaultPriceOracleStorage storage $ = _getStorage();
        __Controllable_init(platform_);

        $.minQuorum = minQuorum_;
        $.maxPriceAge = maxPriceAge_;
        for (uint256 i = 0; i < validators_.length; i++) {
            $.authorizedValidators[validators_[i]] = true;
            $.validatorList.push(validators_[i]);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IVaultPriceOracle
    function submitPrice(address vault_, uint256 price_, uint256 roundId_) external onlyValidator {
        VaultPriceOracleStorage storage $ = _getStorage();
        uint256 currentRoundId = $.vaultPrices[vault_].roundId == 0 ? 1 : $.vaultPrices[vault_].roundId;
        require(roundId_ == currentRoundId, "Invalid roundId");

        $.observations[vault_][currentRoundId][msg.sender] = Observation(price_, block.timestamp);
        emit PriceSubmitted(vault_, msg.sender, price_, currentRoundId);

        if (_countSubmissions(vault_, currentRoundId) >= $.minQuorum) {
            _aggregateAndUpdate(vault_, currentRoundId);
        }
    }

    /// @inheritdoc IVaultPriceOracle
    function addValidator(address validator_) external onlyGovernanceOrMultisig {
        VaultPriceOracleStorage storage $ = _getStorage();
        require(!$.authorizedValidators[validator_], "Validator already authorized");
        $.authorizedValidators[validator_] = true;
        $.validatorList.push(validator_);
        emit ValidatorAdded(validator_);
    }

    /// @inheritdoc IVaultPriceOracle
    function removeValidator(address validator_) external onlyGovernanceOrMultisig {
        VaultPriceOracleStorage storage $ = _getStorage();
        require($.authorizedValidators[validator_], "Validator not authorized");
        $.authorizedValidators[validator_] = false;
        for (uint256 i = 0; i < $.validatorList.length; i++) {
            if ($.validatorList[i] == validator_) {
                $.validatorList[i] = $.validatorList[$.validatorList.length - 1];
                $.validatorList.pop();
                break;
            }
        }
        emit ValidatorRemoved(validator_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


    /// @inheritdoc IVaultPriceOracle
    function getLatestPrice(address vault_) external view returns (uint256 price, uint256 timestamp, uint256 roundId) {
        VaultPriceOracleStorage storage $ = _getStorage();
        AggregatedData memory data = $.vaultPrices[vault_];
        require(data.timestamp > 0, "No data available");
        require(block.timestamp <= data.timestamp + $.maxPriceAge, "Price too old");
        return (data.price, data.timestamp, data.roundId);
    }

    /// @inheritdoc IVaultPriceOracle
    function vaultPrices(address vault_) external view returns (uint256 price, uint256 timestamp, uint256 roundId) {
        VaultPriceOracleStorage storage $ = _getStorage();
        AggregatedData memory data = $.vaultPrices[vault_];
        return (data.price, data.timestamp, data.roundId);
    }

    /// @inheritdoc IVaultPriceOracle
    function observations(address vault_, uint256 roundId_, address validator_) external view returns (uint256 price, uint256 timestamp) {
        VaultPriceOracleStorage storage $ = _getStorage();
        Observation memory data = $.observations[vault_][roundId_][validator_];
        return (data.price, data.timestamp);
    }

    /// @inheritdoc IVaultPriceOracle
    function authorizedValidator(address validator_) external view returns (bool) {
        VaultPriceOracleStorage storage $ = _getStorage();
        return $.authorizedValidators[validator_];
    }

    /// @inheritdoc IVaultPriceOracle
    function validatorList(uint256 index_) external view returns (address) {
        VaultPriceOracleStorage storage $ = _getStorage();
        require(index_ < $.validatorList.length, "Index out of bounds");
        return $.validatorList[index_];
    }

    /// @inheritdoc IVaultPriceOracle
    function validatorListLength() external view returns (uint256) {
        VaultPriceOracleStorage storage $ = _getStorage();
        return $.validatorList.length;
    }

    /// @inheritdoc IVaultPriceOracle
    function minQuorum() external view returns (uint256) {
        VaultPriceOracleStorage storage $ = _getStorage();
        return $.minQuorum;
    }

    /// @inheritdoc IVaultPriceOracle
    function maxPriceAge() external view returns (uint256) {
        VaultPriceOracleStorage storage $ = _getStorage();
        return $.maxPriceAge;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Counts the number of valid price submissions for a vault in a specific round.
    /// @dev Iterates through the list of validators to check if they have submitted a price (non-zero timestamp).
    /// @param vault_ The address of the vault to check submissions for.
    /// @param roundId_ The ID of the round to count submissions for.
    /// @return count The number of valid submissions in the specified round.
    function _countSubmissions(address vault_, uint256 roundId_) internal view returns (uint256) {
        VaultPriceOracleStorage storage $ = _getStorage();
        uint256 count = 0;
        for (uint256 i = 0; i < $.validatorList.length; i++) {
            if ($.observations[vault_][roundId_][$.validatorList[i]].timestamp > 0) {
                count++;
            }
        }
        return count;
    }

    /// @notice Aggregates submitted prices for a vault in a specific round and updates the vault's price data.
    /// @dev Collects valid prices from validators, computes the median, and updates the vault's aggregated data.
    ///      Emits a PriceUpdated event upon successful aggregation.
    /// @param vault_ The address of the vault to aggregate prices for.
    /// @param roundId_ The ID of the round to aggregate.
    function _aggregateAndUpdate(address vault_, uint256 roundId_) internal {
        VaultPriceOracleStorage storage $ = _getStorage();
        uint256[] memory prices = new uint256[]($.validatorList.length);
        uint256 validCount = 0;
        uint256 newRoundId = roundId_ + 1;

        for (uint256 i = 0; i < $.validatorList.length; i++) {
            Observation memory obs = $.observations[vault_][roundId_][$.validatorList[i]];
            if (obs.timestamp > 0) {
                prices[validCount] = obs.price;
                validCount++;
            }
        }

        uint256 medianPrice = _getMedian(prices, validCount);

        $.vaultPrices[vault_] = AggregatedData(medianPrice, block.timestamp, newRoundId);
        emit PriceUpdated(vault_, medianPrice, roundId_, block.timestamp);
    }

    /// @notice Calculates the median value from a list of prices.
    /// @dev Copies valid prices to a new array, sorts it using quicksort, and returns the median.
    ///      For even counts, returns the average of the two middle values; for odd counts, returns the middle value.
    /// @param prices_ The array containing all submitted prices (including unused slots).
    /// @param count_ The number of valid prices in the array.
    /// @return The median price, or 0 if no valid prices are provided.
    function _getMedian(uint256[] memory prices_, uint256 count_) internal pure returns (uint256) {
        if (count_ == 0) return 0;
        uint256[] memory prices = new uint256[](count_);
        for (uint256 i = 0; i < count_; i++) {
            prices[i] = prices_[i];
        }
        _quickSort(prices, 0, count_ - 1);
        if (count_ % 2 == 0) {
            return (prices[count_ / 2 - 1] + prices[count_ / 2]) / 2;
        } else {
            return prices[count_ / 2];
        }
    }

    /// @notice Sorts an array of prices using the quicksort algorithm.
    /// @dev Recursively sorts the array by selecting a pivot and partitioning around it.
    /// @param arr_ The array to sort.
    /// @param low_ The starting index of the subarray to sort.
    /// @param high_ The ending index of the subarray to sort.
    function _quickSort(uint256[] memory arr_, uint256 low_, uint256 high_) internal pure {
        if (low_ < high_) {
            uint256 pi = _partition(arr_, low_, high_);
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
    function _partition(uint256[] memory arr_, uint256 low_, uint256 high_) internal pure returns (uint256) {
        uint256 pivot = arr_[high_];
        uint256 i = low_;

        for (uint256 j = low_; j < high_; j++) {
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
        require($.authorizedValidators[msg.sender], "Not authorized validator");
    }
}