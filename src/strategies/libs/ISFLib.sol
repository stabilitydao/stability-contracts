// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IICHIVaultV4} from "../../integrations/ichi/IICHIVaultV4.sol";
import {CommonLib} from "../../core/libs/CommonLib.sol";
import {IAlgebraPoolErrors} from "../../integrations/algebrav4/pool/IAlgebraPoolErrors.sol";
import {IAlgebraPool} from "../../integrations/algebrav4/IAlgebraPool.sol";
import {IAmmAdapter} from "../../interfaces/IAmmAdapter.sol";
import {ICAmmAdapter} from "../../interfaces/ICAmmAdapter.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IFactory} from "../../interfaces/IFactory.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {IVolatilityOracle} from "../../integrations/algebrav4/IVolatilityOracle.sol";
import {UniswapV3MathLib} from "./UniswapV3MathLib.sol";

library ISFLib {
    uint internal constant PRECISION = 10 ** 18;

    struct PreviewDepositVars {
        uint32 twapPeriod;
        uint32 auxTwapPeriod;
        uint price;
        uint twap;
        uint auxTwap;
        uint pool0;
        uint pool1;
        address pool;
        address token0;
        address token1;
    }

    function previewDepositAssets(
        uint[] memory amountsMax,
        IStrategy.StrategyBaseStorage storage __$__
    ) external view returns (uint[] memory amountsConsumed, uint value) {
        IICHIVaultV4 _underlying = IICHIVaultV4(__$__._underlying);
        amountsConsumed = new uint[](2);
        if (_underlying.allowToken0()) {
            amountsConsumed[0] = amountsMax[0];
        } else {
            amountsConsumed[1] = amountsMax[1];
        }

        PreviewDepositVars memory v;
        v.pool = _underlying.pool();
        v.token0 = _underlying.token0();
        v.token1 = _underlying.token1();

        v.twapPeriod = _underlying.twapPeriod();

        // Get spot price
        v.price = _fetchSpot(_underlying.token0(), _underlying.token1(), _underlying.currentTick(), PRECISION);

        // Get TWAP price
        v.twap = _fetchTwap(v.pool, v.token0, v.token1, v.twapPeriod, PRECISION);

        v.auxTwapPeriod = _underlying.auxTwapPeriod();

        v.auxTwap = v.auxTwapPeriod > 0 ? _fetchTwap(v.pool, v.token0, v.token1, v.auxTwapPeriod, PRECISION) : v.twap;

        (uint pool0, uint pool1) = _underlying.getTotalAmounts();

        // Calculate share value in token1
        uint priceForDeposit = _getConservativePrice(v.price, v.twap, v.auxTwap, false, v.auxTwapPeriod);
        uint deposit0PricedInToken1 = amountsConsumed[0] * priceForDeposit / PRECISION;

        value = amountsConsumed[1] + deposit0PricedInToken1;
        uint totalSupply = _underlying.totalSupply();
        if (totalSupply != 0) {
            uint priceForPool = _getConservativePrice(v.price, v.twap, v.auxTwap, true, v.auxTwapPeriod);
            uint pool0PricedInToken1 = pool0 * priceForPool / PRECISION;
            value = value * totalSupply / (pool0PricedInToken1 + pool1);
        }
    }

    function getAssetsProportions(IICHIVaultV4 _underlying) external view returns (uint[] memory proportions) {
        proportions = new uint[](2);
        if (_underlying.allowToken0()) {
            proportions[0] = 1e18;
        } else {
            proportions[1] = 1e18;
        }
    }

    function initVariants(
        address platform_,
        string memory strategyLogicId,
        string memory ammAdapterId
    )
        external
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        ICAmmAdapter _ammAdapter = ICAmmAdapter(IPlatform(platform_).ammAdapter(keccak256(bytes(ammAdapterId))).proxy);
        addresses = new address[](0);
        ticks = new int24[](0);

        IFactory.Farm[] memory farms = IFactory(IPlatform(platform_).factory()).farms();
        uint len = farms.length;
        //slither-disable-next-line uninitialized-local
        uint localTtotal;
        //nosemgrep
        for (uint i; i < len; ++i) {
            //nosemgrep
            IFactory.Farm memory farm = farms[i];
            //nosemgrep
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyLogicId)) {
                ++localTtotal;
            }
        }

        variants = new string[](localTtotal);
        nums = new uint[](localTtotal);
        localTtotal = 0;
        //nosemgrep
        for (uint i; i < len; ++i) {
            //nosemgrep
            IFactory.Farm memory farm = farms[i];
            //nosemgrep
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyLogicId)) {
                nums[localTtotal] = i;
                //slither-disable-next-line calls-loop
                variants[localTtotal] = generateDescription(farm, _ammAdapter);
                ++localTtotal;
            }
        }
    }

    function generateDescription(
        IFactory.Farm memory farm,
        IAmmAdapter _ammAdapter
    ) public view returns (string memory) {
        //slither-disable-next-line calls-loop
        return string.concat(
            "Earn ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(farm.rewardAssets), ", "),
            " and fees on SwapX pool ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(_ammAdapter.poolTokens(farm.pool)), "-"),
            " by Ichi ",
            IERC20Metadata(farm.addresses[0]).symbol()
        );
    }

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
    function consult(address oracleAddress, uint32 period) internal view returns (int24 timeWeightedAverageTick) {
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

    function _assetsAmounts(
        IStrategy.StrategyBaseStorage storage $_
    ) external view returns (address[] memory assets_, uint[] memory amounts_) {
        assets_ = $_._assets;
        uint value = $_.total;
        IICHIVaultV4 _underlying = IICHIVaultV4($_._underlying);
        (uint amount0, uint amount1) = _underlying.getTotalAmounts();
        uint totalSupply = _underlying.totalSupply();
        amounts_ = new uint[](2);
        amounts_[0] = amount0 * value / totalSupply;
        amounts_[1] = amount1 * value / totalSupply;
    }

    uint internal constant BEFORE_SWAP_FLAG = 1;
    uint internal constant AFTER_SWAP_FLAG = 1 << 1;
    uint internal constant BEFORE_POSITION_MODIFY_FLAG = 1 << 2;
    uint internal constant AFTER_POSITION_MODIFY_FLAG = 1 << 3;
    uint internal constant BEFORE_FLASH_FLAG = 1 << 4;
    uint internal constant AFTER_FLASH_FLAG = 1 << 5;
    uint internal constant AFTER_INIT_FLAG = 1 << 6;
    uint internal constant DYNAMIC_FEE = 1 << 7;

    /**
     * @notice returns equivalent _tokenOut for _amountIn, _tokenIn using spot price
     *  @param _tokenIn token the input amount is in
     *  @param _tokenOut token for the output amount
     *  @param _tick tick for the spot price
     *  @param _amountIn amount in _tokenIn
     *  @return amountOut equivalent anount in _tokenOut
     */
    function _fetchSpot(
        address _tokenIn,
        address _tokenOut,
        int24 _tick,
        uint _amountIn
    ) internal pure returns (uint amountOut) {
        return getQuoteAtTick(_tick, SafeCast.toUint128(_amountIn), _tokenIn, _tokenOut);
    }

    /**
     * @notice returns equivalent _tokenOut for _amountIn, _tokenIn using TWAP price
     *  @param _pool Uniswap V3 pool address to be used for price checking
     *  @param _tokenIn token the input amount is in
     *  @param _tokenOut token for the output amount
     *  @param _twapPeriod the averaging time period
     *  @param _amountIn amount in _tokenIn
     *  @return amountOut equivalent anount in _tokenOut
     */
    function _fetchTwap(
        address _pool,
        address _tokenIn,
        address _tokenOut,
        uint32 _twapPeriod,
        uint _amountIn
    ) internal view returns (uint amountOut) {
        // Leave twapTick as a int256 to avoid solidity casting
        address basePlugin = _getBasePluginFromPool(_pool);

        int twapTick = consult(basePlugin, _twapPeriod);
        return getQuoteAtTick(
            int24(twapTick), // can assume safe being result from consult()
            SafeCast.toUint128(_amountIn),
            _tokenIn,
            _tokenOut
        );
    }

    function _getBasePluginFromPool(address pool_) private view returns (address basePlugin) {
        basePlugin = IAlgebraPool(pool_).plugin();
        // make sure the base plugin is connected to the pool
        require(isOracleConnectedToPool(basePlugin, pool_), "IV: diconnected plugin");
    }

    /**
     * @notice Helper function to get the most conservative price
     *  @param spot Current spot price
     *  @param twap TWAP price
     *  @param auxTwap Auxiliary TWAP price
     *  @param isPool Flag indicating if the valuation is for the pool or deposit
     *  @return price Most conservative price
     */
    function _getConservativePrice(
        uint spot,
        uint twap,
        uint auxTwap,
        bool isPool,
        uint32 auxTwapPeriod
    ) internal pure returns (uint) {
        if (isPool) {
            // For pool valuation, use highest price to be conservative
            if (auxTwapPeriod > 0) {
                return Math.max(Math.max(spot, twap), auxTwap);
            }
            return Math.max(spot, twap);
        } else {
            // For deposit valuation, use lowest price to be conservative
            if (auxTwapPeriod > 0) {
                return Math.min(Math.min(spot, twap), auxTwap);
            }
            return Math.min(spot, twap);
        }
    }
}
