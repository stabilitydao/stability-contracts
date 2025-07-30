// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../interfaces/IVaultPriceOracle.sol";
import "./base/Controllable.sol";

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
        mapping(address => bool) authorizedValidators;
        address[] validatorList;
        uint256 minQuorum;
        uint256 maxPriceAge;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyValidator() {
        VaultPriceOracleStorage storage $ = _getStorage();
        require($.authorizedValidators[msg.sender], "Not authorized validator");
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IVaultPriceOracle
    function initialize(address platform_, uint256 _minQuorum, address[] memory _validators, uint256 _maxPriceAge) public initializer {
        VaultPriceOracleStorage storage $ = _getStorage();
        __Controllable_init(platform_);

        $.minQuorum = _minQuorum;
        $.maxPriceAge = _maxPriceAge;
        for (uint256 i = 0; i < _validators.length; i++) {
            $.authorizedValidators[_validators[i]] = true;
            $.validatorList.push(_validators[i]);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IVaultPriceOracle
    function submitPrice(address _vault, uint256 _price, uint256 _roundId) external onlyValidator {
        VaultPriceOracleStorage storage $ = _getStorage();
        uint256 currentRoundId = $.vaultPrices[_vault].roundId == 0 ? 1 : $.vaultPrices[_vault].roundId;
        require(_roundId == currentRoundId, "Invalid roundId");

        $.observations[_vault][currentRoundId][msg.sender] = Observation(_price, block.timestamp);
        emit PriceSubmitted(_vault, msg.sender, _price, currentRoundId);

        if (_countSubmissions(_vault, currentRoundId) >= $.minQuorum) {
            _aggregateAndUpdate(_vault, currentRoundId);
        }
    }

    /// @inheritdoc IVaultPriceOracle
    function addValidator(address _validator) external onlyGovernanceOrMultisig {
        VaultPriceOracleStorage storage $ = _getStorage();
        require(!$.authorizedValidators[_validator], "Validator already authorized");
        $.authorizedValidators[_validator] = true;
        $.validatorList.push(_validator);
        emit ValidatorAdded(_validator);
    }

    /// @inheritdoc IVaultPriceOracle
    function removeValidator(address _validator) external onlyGovernanceOrMultisig {
        VaultPriceOracleStorage storage $ = _getStorage();
        require($.authorizedValidators[_validator], "Validator not authorized");
        $.authorizedValidators[_validator] = false;
        for (uint256 i = 0; i < $.validatorList.length; i++) {
            if ($.validatorList[i] == _validator) {
                $.validatorList[i] = $.validatorList[$.validatorList.length - 1];
                $.validatorList.pop();
                break;
            }
        }
        emit ValidatorRemoved(_validator);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


    /// @inheritdoc IVaultPriceOracle
    function getLatestPrice(address _vault) external view returns (uint256 price, uint256 timestamp, uint256 roundId) {
        VaultPriceOracleStorage storage $ = _getStorage();
        AggregatedData memory data = $.vaultPrices[_vault];
        require(data.timestamp > 0, "No data available");
        require(block.timestamp <= data.timestamp + $.maxPriceAge, "Price too old");
        return (data.price, data.timestamp, data.roundId);
    }

    /// @inheritdoc IVaultPriceOracle
    function vaultPrices(address vault) external view returns (uint256 price, uint256 timestamp, uint256 roundId) {
        VaultPriceOracleStorage storage $ = _getStorage();
        AggregatedData memory data = $.vaultPrices[vault];
        return (data.price, data.timestamp, data.roundId);
    }

    /// @inheritdoc IVaultPriceOracle
    function observations(address vault, uint256 roundId, address validator) external view returns (uint256 price, uint256 timestamp) {
        VaultPriceOracleStorage storage $ = _getStorage();
        Observation memory data = $.observations[vault][roundId][validator];
        return (data.price, data.timestamp);
    }

    /// @inheritdoc IVaultPriceOracle
    function authorizedValidator(address validator) external view returns (bool) {
        VaultPriceOracleStorage storage $ = _getStorage();
        return $.authorizedValidators[validator];
    }

    /// @inheritdoc IVaultPriceOracle
    function validatorList(uint256 index) external view returns (address) {
        VaultPriceOracleStorage storage $ = _getStorage();
        require(index < $.validatorList.length, "Index out of bounds");
        return $.validatorList[index];
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
    /// @param _vault The address of the vault to check submissions for.
    /// @param _roundId The ID of the round to count submissions for.
    /// @return count The number of valid submissions in the specified round.
    function _countSubmissions(address _vault, uint256 _roundId) internal view returns (uint256) {
        VaultPriceOracleStorage storage $ = _getStorage();
        uint256 count = 0;
        for (uint256 i = 0; i < $.validatorList.length; i++) {
            if ($.observations[_vault][_roundId][$.validatorList[i]].timestamp > 0) {
                count++;
            }
        }
        return count;
    }

    /// @notice Aggregates submitted prices for a vault in a specific round and updates the vault's price data.
    /// @dev Collects valid prices from validators, computes the median, and updates the vault's aggregated data.
    ///      Emits a PriceUpdated event upon successful aggregation.
    /// @param _vault The address of the vault to aggregate prices for.
    /// @param _roundId The ID of the round to aggregate.
    function _aggregateAndUpdate(address _vault, uint256 _roundId) internal {
        VaultPriceOracleStorage storage $ = _getStorage();
        uint256[] memory prices = new uint256[]($.validatorList.length);
        uint256 validCount = 0;

        for (uint256 i = 0; i < $.validatorList.length; i++) {
            Observation memory obs = $.observations[_vault][_roundId][$.validatorList[i]];
            if (obs.timestamp > 0) {
                prices[validCount] = obs.price;
                validCount++;
            }
        }

        uint256 medianPrice = _getMedian(prices, validCount);

        $.vaultPrices[_vault] = AggregatedData(medianPrice, block.timestamp, _roundId);
        emit PriceUpdated(_vault, medianPrice, _roundId, block.timestamp);
    }

    /// @notice Calculates the median value from a list of prices.
    /// @dev Copies valid prices to a new array, sorts it using quicksort, and returns the median.
    ///      For even counts, returns the average of the two middle values; for odd counts, returns the middle value.
    /// @param _prices The array containing all submitted prices (including unused slots).
    /// @param _count The number of valid prices in the array.
    /// @return The median price, or 0 if no valid prices are provided.
    function _getMedian(uint256[] memory _prices, uint256 _count) internal pure returns (uint256) {
        if (_count == 0) return 0;
        uint256[] memory prices = new uint256[](_count);
        for (uint256 i = 0; i < _count; i++) {
            prices[i] = _prices[i];
        }
        _quickSort(prices, 0, _count - 1);
        if (_count % 2 == 0) {
            return (prices[_count / 2 - 1] + prices[_count / 2]) / 2;
        } else {
            return prices[_count / 2];
        }
    }

    /// @notice Sorts an array of prices using the quicksort algorithm.
    /// @dev Recursively sorts the array by selecting a pivot and partitioning around it.
    /// @param arr The array to sort.
    /// @param low The starting index of the subarray to sort.
    /// @param high The ending index of the subarray to sort.
    function _quickSort(uint256[] memory arr, uint256 low, uint256 high) internal pure {
        if (low < high) {
            uint256 pi = _partition(arr, low, high);
            if (pi > 0) {
                _quickSort(arr, low, pi - 1);
            }
            _quickSort(arr, pi + 1, high);
        }
    }

    /// @notice Partitions an array around a pivot for quicksort.
    /// @dev Selects the last element as the pivot and rearranges elements so that smaller ones are on the left.
    /// @param arr The array to partition.
    /// @param low The starting index of the subarray.
    /// @param high The ending index of the subarray (pivot location).
    /// @return The index of the pivot after partitioning.
    function _partition(uint256[] memory arr, uint256 low, uint256 high) internal pure returns (uint256) {
        uint256 pivot = arr[high];
        uint256 i = low;

        for (uint256 j = low; j < high; j++) {
            if (arr[j] <= pivot) {
                (arr[i], arr[j]) = (arr[j], arr[i]);
                i++;
            }
        }
        (arr[i], arr[high]) = (arr[high], arr[i]);
        return i;
    }

    function _getStorage() private pure returns (VaultPriceOracleStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := VAULT_PRICE_ORACLE_STORAGE_LOCATION
        }
    }
}