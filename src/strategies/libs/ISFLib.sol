// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IVolatilityOracle} from "../../integrations/algebrav4/IVolatilityOracle.sol";
import {UniswapV3MathLib} from "./UniswapV3MathLib.sol";
import {IAlgebraPool} from "../../integrations/algebrav4/IAlgebraPool.sol";
import {IAlgebraPoolErrors} from "../../integrations/algebrav4/pool/IAlgebraPoolErrors.sol";

library ISFLib {
    /// @notice Checks if the oracle is currently connected to the pool
    /// @param oracleAddress The address of oracle
    /// @param oracleAddress The address of the pool
    /// @return connected Whether or not the oracle is connected
    function isOracleConnectedToPool(
        address oracleAddress,
        address poolAddress
    ) internal view returns (bool connected) {
        if (oracleAddress == address(0)) {
            return false;
        }

        IAlgebraPool pool = IAlgebraPool(poolAddress);
        if (oracleAddress == pool.plugin()) {
            (,,, uint8 pluginConfig,,) = pool.globalState();
            connected = hasFlag(pluginConfig, BEFORE_SWAP_FLAG);
        }
    }

    /// @notice Given a tick and a token amount, calculates the amount of token received in exchange
    /// @param tick Tick value used to calculate the quote
    /// @param baseAmount Amount of token to be converted
    /// @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
    /// @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
    /// @return quoteAmount Amount of quoteToken received for baseAmount of baseToken
    function getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal pure returns (uint quoteAmount) {
        uint160 sqrtRatioX96 = UniswapV3MathLib.getSqrtRatioAtTick(tick);
        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint ratioX192 = uint(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? UniswapV3MathLib.mulDiv(ratioX192, baseAmount, 1 << 192)
                : UniswapV3MathLib.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint ratioX128 = UniswapV3MathLib.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? UniswapV3MathLib.mulDiv(ratioX128, baseAmount, 1 << 128)
                : UniswapV3MathLib.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }

    /// @notice Fetches time-weighted average tick using Algebra VolatilityOracle
    /// @param oracleAddress The address of oracle
    /// @param period Number of seconds in the past to start calculating time-weighted average
    /// @return timeWeightedAverageTick The time-weighted average tick from (block.timestamp-period) to block.timestamp
    function consult(address oracleAddress, uint32 period) external view returns (int24 timeWeightedAverageTick) {
        require(period != 0, "Period is zero");

        uint32[] memory secondAgos = new uint32[](2);
        secondAgos[0] = period;
        secondAgos[1] = 0;

        IVolatilityOracle oracle = IVolatilityOracle(oracleAddress);
        (int56[] memory tickCumulatives,) = oracle.getTimepoints(secondAgos);
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        timeWeightedAverageTick = int24(tickCumulativesDelta / int56(uint56(period)));

        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(period)) != 0)) timeWeightedAverageTick--;
    }

    function hasFlag(uint8 pluginConfig, uint flag) internal pure returns (bool res) {
        assembly {
            res := gt(and(pluginConfig, flag), 0)
        }
    }

    function shouldReturn(bytes4 selector, bytes4 expectedSelector) internal pure {
        if (selector != expectedSelector) revert IAlgebraPoolErrors.invalidHookResponse(expectedSelector);
    }

    uint internal constant BEFORE_SWAP_FLAG = 1;
    uint internal constant AFTER_SWAP_FLAG = 1 << 1;
    uint internal constant BEFORE_POSITION_MODIFY_FLAG = 1 << 2;
    uint internal constant AFTER_POSITION_MODIFY_FLAG = 1 << 3;
    uint internal constant BEFORE_FLASH_FLAG = 1 << 4;
    uint internal constant AFTER_FLASH_FLAG = 1 << 5;
    uint internal constant AFTER_INIT_FLAG = 1 << 6;
    uint internal constant DYNAMIC_FEE = 1 << 7;
}
