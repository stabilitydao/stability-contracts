// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IICHIVaultV4} from "../../integrations/ichi/IICHIVaultV4.sol";
import {UniswapV3MathLib} from "../libs/UniswapV3MathLib.sol";
import {IUniswapV3Pool} from "../../integrations/uniswapv3/IUniswapV3Pool.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {IFarmingStrategy} from "../../interfaces/IFarmingStrategy.sol";
import {IFactory} from "../../interfaces/IFactory.sol";
import {IICHIVaultGateway} from "../../integrations/ichi/IICHIVaultGateway.sol";
import {IGaugeEquivalent} from "../../integrations/equalizer/IGaugeEquivalent.sol";
import {StrategyLib} from "./StrategyLib.sol";
import {IAmmAdapter} from "../../interfaces/IAmmAdapter.sol";
import {CommonLib} from "../../core/libs/CommonLib.sol";

/// @title Library for IEF strategy code splitting
library IEFLib {
    using SafeERC20 for IERC20;

    uint internal constant PRECISION = 10 ** 18;

    uint internal constant MIN_SHARES = 1000;

    function depositAssets(
        uint[] memory amounts,
        bool claimRevenue,
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f,
        IStrategy.StrategyBaseStorage storage $base,
        IFactory.Farm memory farm
    ) external returns (uint value) {
        if (claimRevenue) {
            (,,, uint[] memory rewardAmounts) = _claimRevenue($f, $base, farm);
            uint len = rewardAmounts.length;
            // nosemgrep
            for (uint i; i < len; ++i) {
                // nosemgrep
                $f._rewardsOnBalance[i] += rewardAmounts[i];
            }
        }

        address ichiVault = farm.addresses[1];
        uint initialValue = IERC20(ichiVault).balanceOf(address(this));
        IICHIVaultV4 alm = IICHIVaultV4($base._underlying);
        address token = alm.allowToken0() ? alm.token0() : alm.token1();
        uint amount = alm.allowToken0() ? amounts[0] : amounts[1];

        IICHIVaultGateway(farm.addresses[0]).forwardDepositToICHIVault(
            ichiVault, farm.addresses[2], token, amount, 1, address(this)
        );
        value = IERC20(ichiVault).balanceOf(address(this)) - initialValue;
        IGaugeEquivalent(farm.addresses[3]).deposit(value);
        $base.total += value;
    }

    function depositUnderlying(
        uint amount,
        IFactory.Farm memory farm,
        IStrategy.StrategyBaseStorage storage $base
    ) external returns (uint[] memory amountsConsumed) {
        IGaugeEquivalent(farm.addresses[3]).deposit(amount);
        amountsConsumed = previewDepositUnderlying(amount, $base);
        $base.total += amount;
    }

    function previewDepositUnderlying(
        uint amount,
        IStrategy.StrategyBaseStorage storage $base
    ) public view returns (uint[] memory amountsConsumed) {
        IICHIVaultV4 alm = IICHIVaultV4($base._underlying);
        (uint total0, uint total1) = alm.getTotalAmounts();
        uint totalInAlm = alm.totalSupply();
        amountsConsumed = new uint[](2);
        amountsConsumed[0] = amount * total0 / totalInAlm;
        amountsConsumed[1] = amount * total1 / totalInAlm;
    }

    function withdrawAssets(
        uint value,
        address receiver,
        IFactory.Farm memory farm,
        IStrategy.StrategyBaseStorage storage $base
    ) external returns (uint[] memory amountsOut) {
        IGaugeEquivalent(farm.addresses[3]).withdraw(value);
        amountsOut = new uint[](2);
        (amountsOut[0], amountsOut[1]) = IICHIVaultV4(farm.addresses[1]).withdraw(value, receiver);
        $base.total -= value;
    }

    function withdrawUnderlying(
        uint amount,
        address receiver,
        IFactory.Farm memory farm,
        IStrategy.StrategyBaseStorage storage $base
    ) external {
        IGaugeEquivalent(farm.addresses[3]).withdraw(amount);
        IERC20(farm.addresses[1]).safeTransfer(receiver, amount);
        $base.total -= amount;
    }

    function getAssetsProportions(IStrategy.StrategyBaseStorage storage $base)
        external
        view
        returns (uint[] memory proportions)
    {
        IICHIVaultV4 _underlying = IICHIVaultV4($base._underlying);
        proportions = new uint[](2);
        if (_underlying.allowToken0()) {
            proportions[0] = 1e18;
        } else {
            proportions[1] = 1e18;
        }
    }

    function _claimRevenue(
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f,
        IStrategy.StrategyBaseStorage storage $base,
        IFactory.Farm memory farm
    )
        public
        returns (
            address[] memory __assets,
            uint[] memory __amounts,
            address[] memory __rewardAssets,
            uint[] memory __rewardAmounts
        )
    {
        __assets = $base._assets;
        __amounts = new uint[](__assets.length);
        __rewardAssets = $f._rewardAssets;
        uint rwLen = __rewardAssets.length;
        uint[] memory balanceBefore = new uint[](rwLen);
        __rewardAmounts = new uint[](rwLen);
        for (uint i; i < rwLen; ++i) {
            balanceBefore[i] = StrategyLib.balance(__rewardAssets[i]);
        }
        IGaugeEquivalent(farm.addresses[3]).getReward(address(this), __rewardAssets);
        for (uint i; i < rwLen; ++i) {
            __rewardAmounts[i] = StrategyLib.balance(__rewardAssets[i]) - balanceBefore[i];
        }
    }

    function previewDepositAssets(
        uint[] memory amountsMax,
        IStrategy.StrategyBaseStorage storage $base
    ) external view returns (uint[] memory amountsConsumed, uint value) {
        IICHIVaultV4 _underlying = IICHIVaultV4($base._underlying);
        amountsConsumed = new uint[](2);

        if (_underlying.allowToken0()) {
            amountsConsumed[0] = amountsMax[0];
        } else {
            amountsConsumed[1] = amountsMax[1];
        }

        // Get the Spot Price
        uint price = _fetchSpot(_underlying.token0(), _underlying.token1(), _underlying.currentTick(), PRECISION);

        // Get the TWAP
        uint twap = _fetchTwap(
            _underlying.pool(), _underlying.token0(), _underlying.token1(), _underlying.twapPeriod(), PRECISION
        );

        uint32 auxTwapPeriod = _underlying.auxTwapPeriod();
        // Get aux TWAP if aux period is set (otherwise set it equal to the TWAP price)
        uint auxTwap = auxTwapPeriod > 0
            ? _fetchTwap(_underlying.pool(), _underlying.token0(), _underlying.token1(), auxTwapPeriod, PRECISION)
            : twap;

        // Check price manipulation
        _checkPriceManipulation(price, twap, auxTwap, address(_underlying));

        (uint pool0, uint pool1) = _underlying.getTotalAmounts();

        // aggregated deposit
        uint priceForDeposit = _getConservativePrice(price, twap, auxTwap, false, auxTwapPeriod);
        uint deposit0PricedInToken1 = (amountsConsumed[0] * priceForDeposit) / PRECISION;

        value = amountsConsumed[1] + deposit0PricedInToken1;

        uint totalSupply = _underlying.totalSupply();
        if (totalSupply != 0) {
            uint priceForPool = _getConservativePrice(price, twap, auxTwap, true, auxTwapPeriod);
            uint pool0PricedInToken1 = (pool0 * priceForPool) / PRECISION;
            value = (value * totalSupply) / (pool0PricedInToken1 + pool1);
        } else {
            value = value * MIN_SHARES;
        }
    }

    /**
     * @notice returns equivalent _tokenOut for _amountIn, _tokenIn using spot price
     *  @param _tokenIn token the input amount is in
     *  @param _tokenOut token for the output amount
     *  @param _tick tick for the spot price
     *  @param _amountIn amount in _tokenIn
     *  @param amountOut equivalent anount in _tokenOut
     */
    function _fetchSpot(
        address _tokenIn,
        address _tokenOut,
        int24 _tick,
        uint _amountIn
    ) internal pure returns (uint amountOut) {
        return getQuoteAtTick(_tick, SafeCast.toUint128(_amountIn), _tokenIn, _tokenOut);
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

    /**
     * @notice returns equivalent _tokenOut for _amountIn, _tokenIn using TWAP price
     *  @param _pool Uniswap V3 pool address to be used for price checking
     *  @param _tokenIn token the input amount is in
     *  @param _tokenOut token for the output amount
     *  @param _twapPeriod the averaging time period
     *  @param _amountIn amount in _tokenIn
     *  @param amountOut equivalent anount in _tokenOut
     */
    function _fetchTwap(
        address _pool,
        address _tokenIn,
        address _tokenOut,
        uint32 _twapPeriod,
        uint _amountIn
    ) internal view returns (uint amountOut) {
        // Leave twapTick as a int256 to avoid solidity casting
        int twapTick = consult(_pool, _twapPeriod);
        return getQuoteAtTick(
            int24(twapTick), // can assume safe being result from consult()
            SafeCast.toUint128(_amountIn),
            _tokenIn,
            _tokenOut
        );
    }

    /// @notice Fetches time-weighted average tick using UniswapV3 dataStorage
    /// @param pool Address of UniswapV3 pool that we want to getTimepoints
    /// @param period Number of seconds in the past to start calculating time-weighted average
    /// @return timeWeightedAverageTick The time-weighted average tick from (block.timestamp - period) to block.timestamp
    function consult(address pool, uint32 period) internal view returns (int24 timeWeightedAverageTick) {
        require(period != 0, "BP");

        uint32[] memory secondAgos = new uint32[](2);
        secondAgos[0] = period;
        secondAgos[1] = 0;

        (int56[] memory tickCumulatives,) = IUniswapV3Pool(pool).observe(secondAgos);
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        timeWeightedAverageTick = int24(tickCumulativesDelta / int56(int32(period)));

        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(int32(period)) != 0)) timeWeightedAverageTick--;
    }

    /**
     * @notice Helper function to check price manipulation
     *  @param price Current spot price
     *  @param twap TWAP price
     *  @param auxTwap Auxiliary TWAP price
     */
    function _checkPriceManipulation(uint price, uint twap, uint auxTwap, address vault) internal view {
        IICHIVaultV4 _underlying = IICHIVaultV4(vault);

        uint delta = (price > twap) ? ((price - twap) * PRECISION) / price : ((twap - price) * PRECISION) / twap;

        uint hysteresis = _underlying.hysteresis();
        if (_underlying.auxTwapPeriod() > 0) {
            uint auxDelta =
                (price > auxTwap) ? ((price - auxTwap) * PRECISION) / price : ((auxTwap - price) * PRECISION) / auxTwap;

            if (delta > hysteresis || auxDelta > hysteresis) {
                require(checkHysteresis(vault), "IV16");
            }
        } else if (delta > hysteresis) {
            require(checkHysteresis(vault), "IV17");
        }
    }

    /**
     * @notice Checks if the last price change happened in the current block
     */
    function checkHysteresis(address vault) private view returns (bool) {
        IICHIVaultV4 _underlying = IICHIVaultV4(vault);

        //slither-disable-next-line unused-return
        (,, uint16 observationIndex,,,,) = IUniswapV3Pool(_underlying.pool()).slot0();
        //slither-disable-next-line unused-return
        (uint32 blockTimestamp,,,) = IUniswapV3Pool(_underlying.pool()).observations(observationIndex);
        //slither-disable-next-line timestamp
        return (block.timestamp != blockTimestamp);
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

    function generateDescription(
        IFactory.Farm memory farm,
        IAmmAdapter _ammAdapter
    ) external view returns (string memory) {
        //slither-disable-next-line calls-loop
        return string.concat(
            "Earn ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(farm.rewardAssets), ", "),
            " on Equalizer by ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(_ammAdapter.poolTokens(farm.pool)), "-"),
            " Ichi ",
            //slither-disable-next-line calls-loop
            IERC20Metadata(farm.addresses[1]).symbol()
        );
    }
}
