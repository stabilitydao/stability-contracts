// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {ConstantsLib} from "../core/libs/ConstantsLib.sol";
import {AmmAdapterIdLib} from "../adapters/libs/AmmAdapterIdLib.sol";
import {UniswapV3MathLib} from "../strategies/libs/UniswapV3MathLib.sol";
import {ICAmmAdapter} from "../interfaces/ICAmmAdapter.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {IRamsesV3Pool} from "../integrations/pharaohv3/IRamsesV3Pool.sol";

/// @notice AMM adapter for working with Pharaoh V3 AMMs.
/// @dev Same as Uniswap V3 but slot0() has different ABI
/// @author Omriss (https://github.com/omriss)
/// Changelog:
contract PharaohV3Adapter is Controllable, ICAmmAdapter {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    error TwaTickOutOfRange();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function init(address platform_) external initializer {
        __Controllable_init(platform_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CALLBACKS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // nosemgrep
    function uniswapV3SwapCallback(
        //slither-disable-next-line similar-names
        int amount0Delta,
        int amount1Delta,
        //slither-disable-next-line naming-convention
        bytes calldata _data
    ) external {
        // nosemgrep
        if (amount0Delta <= 0 && amount1Delta <= 0) {
            revert IAmmAdapter.WrongCallbackAmount();
        }
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        IERC20(data.tokenIn).safeTransfer(msg.sender, data.amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    //slither-disable-next-line reentrancy-events
    function swap(
        address pool,
        address tokenIn,
        address tokenOut,
        address recipient,
        uint priceImpactTolerance
    ) external {
        address token0 = IRamsesV3Pool(pool).token0();

        uint balanceBefore = IERC20(tokenOut).balanceOf(recipient);
        uint amount = IERC20(tokenIn).balanceOf(address(this));

        {
            uint priceBefore = getPrice(pool, tokenIn, tokenOut, amount);

            //slither-disable-next-line unused-return
            IRamsesV3Pool(pool)
                .swap(
                    recipient,
                    tokenIn == token0,
                    int(amount),
                    tokenIn == token0 ? UniswapV3MathLib.MIN_SQRT_RATIO : UniswapV3MathLib.MAX_SQRT_RATIO,
                    abi.encode(SwapCallbackData({tokenIn: tokenIn, amount: amount}))
                );

            uint priceAfter = getPrice(pool, tokenIn, tokenOut, amount);

            uint priceImpact = (priceBefore - priceAfter) * ConstantsLib.DENOMINATOR / priceBefore;
            if (priceImpact >= priceImpactTolerance) {
                revert(string(abi.encodePacked("!PRICE ", Strings.toString(priceImpact))));
            }
        }

        uint balanceAfter = IERC20(tokenOut).balanceOf(recipient);
        emit SwapInPool(
            pool,
            tokenIn,
            tokenOut,
            recipient,
            priceImpactTolerance,
            amount,
            balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function ammAdapterId() external pure returns (string memory) {
        return AmmAdapterIdLib.UNISWAPV3;
    }

    /// @inheritdoc IAmmAdapter
    function poolTokens(address pool) external view returns (address[] memory) {
        IRamsesV3Pool _pool = IRamsesV3Pool(pool);
        address[] memory tokens = new address[](2);
        tokens[0] = _pool.token0();
        tokens[1] = _pool.token1();
        return tokens;
    }

    /// @inheritdoc IAmmAdapter
    function getLiquidityForAmounts(address, uint[] memory) external pure returns (uint, uint[] memory) {
        revert IAmmAdapter.NotSupportedByCAMM();
    }

    /// @inheritdoc IAmmAdapter
    function getProportions(address pool) external view returns (uint[] memory) {
        uint[] memory p = new uint[](2);
        //slither-disable-next-line unused-return
        (, int24 tick,,,,,) = IRamsesV3Pool(pool).slot0();
        int24 tickSpacing = IRamsesV3Pool(pool).tickSpacing();
        (int24 lowerTick, int24 upperTick) = UniswapV3MathLib.getTicksInSpacing(tick, tickSpacing);
        p[0] = _getProportion0(pool, lowerTick, upperTick);
        p[1] = 1e18 - p[0];
        return p;
    }

    /// @inheritdoc IAmmAdapter
    //slither-disable-next-line divide-before-multiply
    function getPrice(
        address pool,
        address tokenIn,
        address,
        /*tokenOut*/
        uint amount
    ) public view returns (uint) {
        return _getPrice(pool, tokenIn, amount, 0);
    }

    /// @inheritdoc IAmmAdapter
    function getTwaPrice(
        address pool,
        address tokenIn,
        address,
        /*tokenOut*/
        uint amount,
        uint32 period
    ) public view returns (uint) {
        return _getPrice(pool, tokenIn, amount, period);
    }

    /// @inheritdoc ICAmmAdapter
    function getProportions(address pool, int24[] memory ticks) external view returns (uint[] memory) {
        uint[] memory p = new uint[](2);
        p[0] = _getProportion0(pool, ticks[0], ticks[1]);
        p[1] = 1e18 - p[0];
        return p;
    }

    /// @inheritdoc ICAmmAdapter
    function getLiquidityForAmounts(
        address pool,
        uint[] memory amounts,
        int24[] memory ticks
    ) external view returns (uint liquidity, uint[] memory amountsConsumed) {
        amountsConsumed = new uint[](2);
        (liquidity, amountsConsumed[0], amountsConsumed[1]) =
            _getLiquidityForAmounts(pool, amounts[0], amounts[1], ticks[0], ticks[1]);
    }

    /// @inheritdoc ICAmmAdapter
    function getAmountsForLiquidity(
        address pool,
        int24[] memory ticks,
        uint128 liquidity
    ) external view returns (uint[] memory amounts) {
        amounts = new uint[](2);
        (amounts[0], amounts[1]) = _getAmountsForLiquidity(pool, ticks[0], ticks[1], liquidity);
    }

    /// @inheritdoc ICAmmAdapter
    function getPriceAtTick(address pool, address tokenIn, int24 tick) external view returns (uint) {
        address token0 = IRamsesV3Pool(pool).token0();
        address token1 = IRamsesV3Pool(pool).token1();
        uint tokenInDecimals = tokenIn == token0 ? IERC20Metadata(token0).decimals() : IERC20Metadata(token1).decimals();
        uint tokenOutDecimals =
            tokenIn == token1 ? IERC20Metadata(token0).decimals() : IERC20Metadata(token1).decimals();
        uint160 sqrtPriceX96 = UniswapV3MathLib.getSqrtRatioAtTick(tick);
        return UniswapV3MathLib.calcPriceOut(tokenIn, token0, sqrtPriceX96, tokenInDecimals, tokenOutDecimals, 0);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(Controllable, IERC165) returns (bool) {
        return interfaceId == type(ICAmmAdapter).interfaceId || interfaceId == type(IAmmAdapter).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getProportion0(address pool, int24 lowerTick, int24 upperTick) internal view returns (uint) {
        address token1 = IRamsesV3Pool(pool).token1();
        //slither-disable-next-line unused-return
        (uint160 sqrtRatioX96,,,,,,) = IRamsesV3Pool(pool).slot0();
        uint token1Price = getPrice(pool, token1, address(0), 0);
        uint token1Decimals = IERC20Metadata(token1).decimals();
        //slither-disable-next-line similar-names
        uint token0Desired = token1Price;
        uint token1Desired = 10 ** token1Decimals;
        uint128 liquidityOut =
            UniswapV3MathLib.getLiquidityForAmounts(sqrtRatioX96, lowerTick, upperTick, token0Desired, token1Desired);
        //slither-disable-next-line similar-names
        (uint amount0Consumed, uint amount1Consumed) =
            UniswapV3MathLib.getAmountsForLiquidity(sqrtRatioX96, lowerTick, upperTick, liquidityOut);
        //slither-disable-next-line divide-before-multiply
        uint consumed1Priced = amount1Consumed * token1Price / token1Desired;
        //slither-disable-next-line divide-before-multiply
        return amount0Consumed * 1e18 / (amount0Consumed + consumed1Priced);
    }

    function _getLiquidityForAmounts(
        address pool,
        //slither-disable-next-line similar-names
        uint amount0Desired,
        //slither-disable-next-line similar-names
        uint amount1Desired,
        int24 lowerTick,
        int24 upperTick
    )
        internal
        view
        returns (
            uint liquidity,
            //slither-disable-next-line similar-names
            uint amount0Consumed,
            //slither-disable-next-line similar-names
            uint amount1Consumed
        )
    {
        //slither-disable-next-line unused-return
        (uint160 sqrtRatioX96,,,,,,) = IRamsesV3Pool(pool).slot0();
        uint128 liquidityOut =
            UniswapV3MathLib.getLiquidityForAmounts(sqrtRatioX96, lowerTick, upperTick, amount0Desired, amount1Desired);
        (amount0Consumed, amount1Consumed) =
            UniswapV3MathLib.getAmountsForLiquidity(sqrtRatioX96, lowerTick, upperTick, liquidityOut);
        liquidity = uint(liquidityOut);
    }

    function _getAmountsForLiquidity(
        address pool,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) internal view returns (uint amount0, uint amount1) {
        //slither-disable-next-line unused-return
        (uint160 sqrtRatioX96,,,,,,) = IRamsesV3Pool(pool).slot0();
        (amount0, amount1) = UniswapV3MathLib.getAmountsForLiquidity(sqrtRatioX96, lowerTick, upperTick, liquidity);
    }

    function _getPrice(address pool, address tokenIn, uint amount, uint32 period) internal view returns (uint) {
        address token0 = IRamsesV3Pool(pool).token0();
        address token1 = IRamsesV3Pool(pool).token1();

        uint tokenInDecimals = tokenIn == token0 ? IERC20Metadata(token0).decimals() : IERC20Metadata(token1).decimals();
        uint tokenOutDecimals =
            tokenIn == token1 ? IERC20Metadata(token0).decimals() : IERC20Metadata(token1).decimals();

        uint160 sqrtPriceX96;
        if (period == 0) {
            //slither-disable-next-line unused-return
            (sqrtPriceX96,,,,,,) = IRamsesV3Pool(pool).slot0();
        } else {
            sqrtPriceX96 = _getTwaSqrtPrice(pool, period);
        }

        return UniswapV3MathLib.calcPriceOut(tokenIn, token0, sqrtPriceX96, tokenInDecimals, tokenOutDecimals, amount);
    }

    function _getTwaSqrtPrice(address pool, uint32 period) internal view returns (uint160 sqrtPriceX96) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = uint32(period);
        secondsAgos[1] = 0;

        //slither-disable-next-line unused-return
        (int56[] memory tickCumulatives,) = IRamsesV3Pool(pool).observe(secondsAgos);
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        int56 period56 = int56(int32(uint32(period)));
        int56 twaTick = tickCumulativesDelta / period56;
        require(twaTick >= int56(type(int24).min) && twaTick <= int56(type(int24).max), TwaTickOutOfRange());
        int24 timeWeightedAverageTick = int24(twaTick);

        return UniswapV3MathLib.getSqrtRatioAtTick(timeWeightedAverageTick);
    }
}
