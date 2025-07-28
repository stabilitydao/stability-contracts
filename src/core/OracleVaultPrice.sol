// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../interfaces/IOracleVaultPrice.sol";
import "./base/Controllable.sol";

contract OracleVaultPrice is Controllable, IOracleVaultPrice {

    mapping(address => AggregatedData) public vaultPrices;

    mapping(address => mapping(uint256 => mapping(address => Observation))) public observations;

    mapping(address => bool) public authorizedOracles;
    address[] public oracleList;

    uint256 public minQuorum;
    uint256 public maxPriceAge;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyOracle() {
        require(authorizedOracles[msg.sender], "Not authorized oracle");
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(address platform_, uint256 _minQuorum, address[] memory _oracles, uint256 _maxPriceAge) public initializer {
        __Controllable_init(platform_);

        minQuorum = _minQuorum;
        maxPriceAge = _maxPriceAge;
        for (uint256 i = 0; i < _oracles.length; i++) {
            authorizedOracles[_oracles[i]] = true;
            oracleList.push(_oracles[i]);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function submitPrice(address _vault, uint256 _price, uint256 _roundId) external onlyOracle {
        uint256 currentRoundId = vaultPrices[_vault].roundId == 0 ? 1 : vaultPrices[_vault].roundId;
        require(_roundId == currentRoundId, "Invalid roundId");

        observations[_vault][currentRoundId][msg.sender] = Observation(_price, block.timestamp);
        emit PriceSubmitted(_vault, msg.sender, _price, currentRoundId);

        if (countSubmissions(_vault, currentRoundId) >= minQuorum) {
            aggregateAndUpdate(_vault, currentRoundId);
        }
    }

    function addOracle(address _oracle) external onlyGovernanceOrMultisig {
        require(!authorizedOracles[_oracle], "Oracle already authorized");
        authorizedOracles[_oracle] = true;
        oracleList.push(_oracle);
    }

    function removeOracle(address _oracle) external onlyGovernanceOrMultisig {
        require(authorizedOracles[_oracle], "Oracle not authorized");
        authorizedOracles[_oracle] = false;
        for (uint256 i = 0; i < oracleList.length; i++) {
            if (oracleList[i] == _oracle) {
                oracleList[i] = oracleList[oracleList.length - 1];
                oracleList.pop();
                break;
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


    function getLatestPrice(address _vault) external view returns (uint256 price, uint256 timestamp, uint256 roundId) {
        AggregatedData memory data = vaultPrices[_vault];
        require(data.timestamp > 0, "No data available");
        require(block.timestamp <= data.timestamp + maxPriceAge, "Price too old");
        return (data.price, data.timestamp, data.roundId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function countSubmissions(address _vault, uint256 _roundId) internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < oracleList.length; i++) {
            if (observations[_vault][_roundId][oracleList[i]].timestamp > 0) {
                count++;
            }
        }
        return count;
    }

    function aggregateAndUpdate(address _vault, uint256 _roundId) internal {
        uint256[] memory prices = new uint256[](oracleList.length);
        uint256 validCount = 0;

        for (uint256 i = 0; i < oracleList.length; i++) {
            Observation memory obs = observations[_vault][_roundId][oracleList[i]];
            if (obs.timestamp > 0) {
                prices[validCount] = obs.price;
                validCount++;
            }
        }

        uint256 medianPrice = getMedian(prices, validCount);

        vaultPrices[_vault] = AggregatedData(medianPrice, block.timestamp, _roundId);
        emit PriceUpdated(_vault, medianPrice, _roundId, block.timestamp);
    }

    function getMedian(uint256[] memory _prices, uint256 _count) internal pure returns (uint256) {
        if (_count == 0) return 0;
        uint256[] memory prices = new uint256[](_count);
        for (uint256 i = 0; i < _count; i++) {
            prices[i] = _prices[i];
        }
        quickSort(prices, 0, _count - 1);
        if (_count % 2 == 0) {
            return (prices[_count / 2 - 1] + prices[_count / 2]) / 2;
        } else {
            return prices[_count / 2];
        }
    }

    function quickSort(uint256[] memory arr, uint256 low, uint256 high) internal pure {
        if (low < high) {
            uint256 pi = partition(arr, low, high);
            if (pi > 0) {
                quickSort(arr, low, pi - 1);
            }
            quickSort(arr, pi + 1, high);
        }
    }

    function partition(uint256[] memory arr, uint256 low, uint256 high) internal pure returns (uint256) {
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
}