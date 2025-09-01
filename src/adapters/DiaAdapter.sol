// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IOracleAdapter} from "../interfaces/IOracleAdapter.sol";
import {IOracle} from "../integrations/dia/IOracle.sol";

/// @title Oracle adapter for Dia oracles
/// Changelog:
///   1.1.0: add updatePriceFeed; only gov or multisig can removePriceFeeds
/// @author Alien Deployer (https://github.com/a17)
/// @custom:deprecated The adapter was used on Real only and now it's not used anymore
/// If we decided to use it on other chain we need to add new tests for it
contract DiaAdapter is Controllable, IOracleAdapter {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Exclude from coverage report
    function test() public {}

    /// @inheritdoc IControllable
    string public constant VERSION = "1.1.0";

    /// @inheritdoc IOracleAdapter
    mapping(address asset => address priceFeed) public priceFeeds;

    EnumerableSet.AddressSet internal _assets;

    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
    }

    /// @inheritdoc IOracleAdapter
    function addPriceFeeds(address[] memory assets_, address[] memory priceFeeds_) external onlyOperator {
        uint len = assets_.length;
        if (len != priceFeeds_.length) {
            revert IControllable.IncorrectArrayLength();
        }
        // nosemgrep
        for (uint i; i < len; ++i) {
            // nosemgrep
            if (!_assets.add(assets_[i])) {
                revert IControllable.AlreadyExist();
            }
            // nosemgrep
            priceFeeds[assets_[i]] = priceFeeds_[i];
        }

        emit NewPriceFeeds(assets_, priceFeeds_);
    }

    /// @inheritdoc IOracleAdapter
    function updatePriceFeed(address asset, address priceFeed) external onlyGovernanceOrMultisig {
        if (!_assets.contains(asset)) {
            revert IControllable.NotExist();
        }
        priceFeeds[asset] = priceFeed;
        emit UpdatedPriceFeed(asset, priceFeed);
    }

    /// @inheritdoc IOracleAdapter
    function removePriceFeeds(address[] memory assets_) external onlyGovernanceOrMultisig {
        uint len = assets_.length;
        // nosemgrep
        for (uint i; i < len; ++i) {
            // nosemgrep
            if (!_assets.remove(assets_[i])) {
                revert IControllable.NotExist();
            }
            // nosemgrep
            priceFeeds[assets_[i]] = address(0);
        }
        emit RemovedPriceFeeds(assets_);
    }

    /// @inheritdoc IOracleAdapter
    function getPrice(address asset) external view returns (uint price, uint timestamp) {
        if (!_assets.contains(asset)) {
            return (0, 0);
        }

        price = IOracle(priceFeeds[asset]).latestPrice();
    }

    /// @inheritdoc IOracleAdapter
    function getAllPrices()
        external
        view
        returns (address[] memory assets_, uint[] memory prices, uint[] memory timestamps)
    {
        uint len = _assets.length();
        assets_ = _assets.values();
        prices = new uint[](len);
        timestamps = new uint[](len);
        // nosemgrep
        for (uint i; i < len; ++i) {
            //slither-disable-next-line calls-loop
            prices[i] = IOracle(priceFeeds[assets_[i]]).latestPrice(); // nosemgrep
            timestamps[i] = 0;
        }
    }

    /// @inheritdoc IOracleAdapter
    function assets() external view returns (address[] memory) {
        return _assets.values();
    }
}
