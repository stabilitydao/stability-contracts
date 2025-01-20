// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IOracleAdapter} from "../interfaces/IOracleAdapter.sol";
import {IAggregatorV3Interface} from "../integrations/chainlink/IAggregatorV3Interface.sol";

/// @title Oracle adapter for Chainlink-compatible price feeds with 8 decimals
/// Changelog:
///   1.1.0: add updatePriceFeed; only gov or multisig can removePriceFeeds
/// @author JodsMigel (https://github.com/JodsMigel)
contract ChainlinkAdapter is Controllable, IOracleAdapter {
    using EnumerableSet for EnumerableSet.AddressSet;

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
        //slither-disable-next-line unused-return
        (, int answer,, uint updatedAt,) = IAggregatorV3Interface(priceFeeds[asset]).latestRoundData();
        return (uint(answer) * 1e10, updatedAt);
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
            (, int answer,, uint updatedAt,) = IAggregatorV3Interface(priceFeeds[assets_[i]]).latestRoundData(); // nosemgrep
            prices[i] = uint(answer) * 1e10;
            timestamps[i] = updatedAt;
        }
    }

    /// @inheritdoc IOracleAdapter
    function assets() external view returns (address[] memory) {
        return _assets.values();
    }
}
