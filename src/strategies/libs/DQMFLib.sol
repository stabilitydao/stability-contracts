// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/Strings.sol";
import "./ALMPositionNameLib.sol";
import "../../core/libs/CommonLib.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IAmmAdapter.sol";
import {IDefiEdgeStrategyFactory} from "../../integrations/defiedge/IDefiEdgeStrategyFactory.sol";
import {IFeedRegistryInterface} from "../../integrations/chainlink/IFeedRegistryInterface.sol";
import {UniswapV3MathLib} from "./UniswapV3MathLib.sol";

library DQMFLib {
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant USD = address(840);

    function generateDescription(
        IFactory.Farm memory farm,
        IAmmAdapter ammAdapter
    ) external view returns (string memory) {
        //slither-disable-next-line calls-loop
        return string.concat(
            "Earn ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(farm.rewardAssets), ", "),
            " on QuickSwap by ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(ammAdapter.poolTokens(farm.pool)), "-"),
            " DefiEdge ",
            //slither-disable-next-line calls-loop
            ALMPositionNameLib.getName(farm.nums[0]),
            " strategy ",
            shortAddress(farm.addresses[0])
        );
    }

    function shortAddress(address addr) public pure returns (string memory) {
        bytes memory s = bytes(Strings.toHexString(addr));
        bytes memory shortAddr = new bytes(12);
        shortAddr[0] = "0";
        shortAddr[1] = "x";
        shortAddr[2] = s[2];
        shortAddr[3] = s[3];
        shortAddr[4] = s[4];
        shortAddr[5] = s[5];
        shortAddr[6] = ".";
        shortAddr[7] = ".";
        shortAddr[8] = s[38];
        shortAddr[9] = s[39];
        shortAddr[10] = s[40];
        shortAddr[11] = s[41];
        return string(shortAddr);
    }

    /// @dev Calculates the shares to be given for specific position for DefiEdge strategy
    /// @param _factory DefiEdge strategy factory
    /// @param _registry Chainlink registry interface
    /// @param _poolTokens Algebra pool tokens
    /// @param _isBase Is USD used as base
    /// @param _amount0 Amount of token0
    /// @param _amount1 Amount of token1
    /// @param _totalAmount0 Total amount of token0
    /// @param _totalAmount1 Total amount of token1
    /// @param _totalShares Total Number of shares
    function calculateShares(
        IDefiEdgeStrategyFactory _factory,
        IFeedRegistryInterface _registry,
        address[] memory _poolTokens,
        bool[2] memory _isBase,
        uint _amount0,
        uint _amount1,
        uint _totalAmount0,
        uint _totalAmount1,
        uint _totalShares
    ) external view returns (uint share) {
        uint __amount0 = _normalise(_poolTokens[0], _amount0);
        uint __amount1 = _normalise(_poolTokens[1], _amount1);
        _totalAmount0 = _normalise(_poolTokens[0], _totalAmount0);
        _totalAmount1 = _normalise(_poolTokens[1], _totalAmount1);
        uint token0Price = _getPriceInUSD(_factory, _registry, _poolTokens[0], _isBase[0]);
        uint token1Price = _getPriceInUSD(_factory, _registry, _poolTokens[1], _isBase[1]);
        // here we assume that _totalShares always > 0, because defiedge strategy is already inited
        uint numerator = token0Price * __amount0 + token1Price * __amount1;
        uint denominator = token0Price * _totalAmount0 + token1Price * _totalAmount1;
        share = UniswapV3MathLib.mulDiv(numerator, _totalShares, denominator);
    }

    function _normalise(address _token, uint _amount) internal view returns (uint normalised) {
        normalised = _amount;
        uint _decimals = IERC20Metadata(_token).decimals();
        if (_decimals < 18) {
            uint missingDecimals = 18 - _decimals;
            normalised = _amount * 10 ** missingDecimals;
        } else if (_decimals > 18) {
            uint extraDecimals = _decimals - 18;
            normalised = _amount / 10 ** extraDecimals;
        }
    }

    /**
     * @notice Returns latest Chainlink price, and normalise it
     * @param _registry registry
     * @param _base Base Asset
     * @param _quote Quote Asset
     */
    function _getChainlinkPrice(
        IFeedRegistryInterface _registry,
        address _base,
        address _quote,
        uint _validPeriod
    ) internal view returns (uint price) {
        (, int _price,, uint updatedAt,) = _registry.latestRoundData(_base, _quote);

        require(block.timestamp - updatedAt < _validPeriod, "OLD_PRICE");

        if (_price <= 0) {
            return 0;
        }

        // normalise the price to 18 decimals
        uint _decimals = _registry.decimals(_base, _quote);

        if (_decimals < 18) {
            uint missingDecimals = 18 - _decimals;
            price = uint(_price) * 10 ** missingDecimals;
        } else if (_decimals > 18) {
            uint extraDecimals = _decimals - 18;
            price = uint(_price) / (10 ** extraDecimals);
        }

        return price;
    }

    /**
     * @notice Gets price in USD, if USD feed is not available use ETH feed
     * @param _registry Interface of the Chainlink registry
     * @param _token the token we want to convert into USD
     * @param _isBase if the token supports base as USD or requires conversion from ETH
     */
    function _getPriceInUSD(
        IDefiEdgeStrategyFactory _factory,
        IFeedRegistryInterface _registry,
        address _token,
        bool _isBase
    ) internal view returns (uint price) {
        if (_isBase) {
            price = _getChainlinkPrice(_registry, _token, USD, _factory.getHeartBeat(_token, USD));
        } else {
            price = _getChainlinkPrice(_registry, _token, ETH, _factory.getHeartBeat(_token, ETH));

            price = UniswapV3MathLib.mulDiv(
                price, _getChainlinkPrice(_registry, ETH, USD, _factory.getHeartBeat(ETH, USD)), 1e18
            );
        }
    }
}
