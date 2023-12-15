// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/IOracleAdapter.sol";
import "../core/base/Controllable.sol";
import "../integrations/chainlink/IAggregatorV3Interface.sol";

/// @author JodsMigel (https://github.com/JodsMigel)
contract ChainlinkAdapter is Controllable, IOracleAdapter {
    using EnumerableSet for EnumerableSet.AddressSet;

    event NewPriceFeeds(address[] assets, address[] priceFeeds);
    event RemovedPriceFeeds(address[] assets);

    /// @dev Version of ChainlinkAdapter implementation
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

    // USDC/USD 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7
    // USDT/USD 0xf9d5AAC6E5572AEFa6bd64108ff86a222F69B64d
    // ETH/USD 0xF9680D99D6C9589e2a93a78A04A279e509205945
    // MATIC/USD 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0
    // BTC/USD 0xc907E116054Ad103354f2D350FD2514433D57F6f

    function getPrice(address asset) external view returns (uint price, uint timestamp) {
        if (!_assets.contains(asset)) {
            return (0, 0);
        }
        //slither-disable-next-line unused-return
        (, int answer,, uint updatedAt,) = IAggregatorV3Interface(priceFeeds[asset]).latestRoundData();
        return (uint(answer) * 1e10, updatedAt);
    }

    //slither-disable-next-line unused-return
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

    function assets() external view returns (address[] memory) {
        return _assets.values();
    }
}
