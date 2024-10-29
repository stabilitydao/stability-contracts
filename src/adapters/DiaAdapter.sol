// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/IOracleAdapter.sol";
import "../core/base/Controllable.sol";
import {IOracle} from "../integrations/dia/IOracle.sol";

/// @title Oracle adapter for Dia oracles
/// @author Alien Deployer (https://github.com/a17)
contract DiaAdapter is Controllable, IOracleAdapter {
    using EnumerableSet for EnumerableSet.AddressSet;

    event NewPriceFeeds(address[] assets, address[] priceFeeds);
    event RemovedPriceFeeds(address[] assets);

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    mapping(address asset => address priceFeed) public priceFeeds;
    EnumerableSet.AddressSet internal _assets;

    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
    }

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

    function removePriceFeeds(address[] memory assets_) external onlyOperator {
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
