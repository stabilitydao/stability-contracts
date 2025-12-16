// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev slot0 is different from UniswapV3
interface IRamsesV3Pool {
    function _advancePeriod() external;

    function burn(
        uint256 index,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1);

    function collect(
        address recipient,
        uint256 index,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);

    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);

    function factory() external view returns (address);

    function fee() external view returns (uint24);

    function feeGrowthGlobal0X128() external view returns (uint256);

    function feeGrowthGlobal1X128() external view returns (uint256);

    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes memory data
    ) external;

    function grossFeeGrowthGlobal0X128() external view returns (uint256);

    function grossFeeGrowthGlobal1X128() external view returns (uint256);

    function increaseObservationCardinalityNext(
        uint16 observationCardinalityNext
    ) external;

    function initialize(uint160 sqrtPriceX96) external;

    function lastPeriod() external view returns (uint256);

    function liquidity() external view returns (uint128);

    function maxLiquidityPerTick() external view returns (uint128);

    function mint(
        address recipient,
        uint256 index,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes memory data
    ) external returns (uint256 amount0, uint256 amount1);

    function observations(uint256 index)
    external
    view
    returns (
        uint32 blockTimestamp,
        int56 tickCumulative,
        uint160 secondsPerLiquidityCumulativeX128,
        bool initialized
    );

    function observe(uint32[] memory secondsAgos)
    external
    view
    returns (
        int56[] memory tickCumulatives,
        uint160[] memory secondsPerLiquidityCumulativeX128s
    );

    function periods(uint256 period)
    external
    view
    returns (
        uint32 previousPeriod,
        int24 startTick,
        int24 lastTick,
        uint160 endSecondsPerLiquidityPeriodX128
    );

    function positionPeriodSecondsInRange(
        uint256 period,
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper
    ) external view returns (uint256 periodSecondsInsideX96);

    function positions(bytes32 key)
    external
    view
    returns (
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );

    function protocolFees() external view returns (uint128, uint128);

    function readStorage(bytes32[] memory slots)
    external
    view
    returns (bytes32[] memory returnData);

    function setFee(uint24 _fee) external;

    function setFeeProtocol() external;

    function slot0()
    external
    view
    returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint24 feeProtocol,
        bool unlocked
    );

    function snapshotCumulativesInside(int24 tickLower, int24 tickUpper)
    external
    view
    returns (
        int56 tickCumulativeInside,
        uint160 secondsPerLiquidityInsideX128,
        uint32 secondsInside
    );

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes memory data
    ) external returns (int256 amount0, int256 amount1);

    function tickBitmap(int16 tick) external view returns (uint256);

    function tickSpacing() external view returns (int24);

    function ticks(int24 tick)
    external
    view
    returns (
        uint128 liquidityGross,
        int128 liquidityNet,
        uint256 feeGrowthOutside0X128,
        uint256 feeGrowthOutside1X128,
        int56 tickCumulativeOutside,
        uint160 secondsPerLiquidityOutsideX128,
        uint32 secondsOutside,
        bool initialized
    );

    function token0() external view returns (address);

    function token1() external view returns (address);
}
