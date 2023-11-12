// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../core/base/Controllable.sol";
import "../core/libs/ConstantsLib.sol";
import "../strategies/libs/UniswapV3MathLib.sol";
import "../interfaces/IDexAdapter.sol";
import "../integrations/algebra/IAlgebraPool.sol";

/// @notice DeX adapter for working with AlegbraV1 AMMs used in QuickSwapV3.
/// @author Alien Deployer (https://github.com/a17)
contract AlgebraAdapter is Controllable, IDexAdapter {
    using SafeERC20 for IERC20;

    /// @dev Version of AlgebraAdapter implementation
    string public constant VERSION = '1.0.0';

    string internal constant _DEX_ADAPTER_ID = "ALGEBRA";

    /// @inheritdoc IDexAdapter
    function init(address platform_) external initializer {
        __Controllable_init(platform_);
    }

    /// @inheritdoc IDexAdapter
    function poolTokens(address pool) external view returns (address[] memory) {
        IAlgebraPool _pool = IAlgebraPool(pool);
        address[] memory tokens = new address[](2);
        tokens[0] = _pool.token0();
        tokens[1] = _pool.token1();
        return tokens;
    }

    /// @inheritdoc IDexAdapter
    function getLiquidityForAmounts(address, uint[] memory) external pure returns (uint, uint[] memory) {
        revert IDexAdapter.NotSupportedByCAMM();
    }

    /// @inheritdoc IDexAdapter
    function getLiquidityForAmounts(address pool, uint[] memory amounts, int24[] memory ticks) external view returns (uint liquidity, uint[] memory amountsConsumed) {
        //slither-disable-next-line unused-return
        (uint160 sqrtRatioX96, , , , , ,) = IAlgebraPool(pool).globalState();
        uint128 liquidityOut = UniswapV3MathLib.getLiquidityForAmounts(sqrtRatioX96, ticks[0], ticks[1], amounts[0], amounts[1]);
        amountsConsumed = new uint[](2);
        (amountsConsumed[0], amountsConsumed[1]) = UniswapV3MathLib.getAmountsForLiquidity(sqrtRatioX96, ticks[0], ticks[1], liquidityOut);
        liquidity = uint(liquidityOut);
    }

    /// @inheritdoc IDexAdapter
    function getAmountsForLiquidity(address pool, int24[] memory ticks, uint128 liquidity) external view returns (uint[] memory amounts) {
        amounts = new uint[](2);
        (amounts[0], amounts[1]) = getAmountsForLiquidity(pool, ticks[0], ticks[1], liquidity);
    }

    function getAmountsForLiquidity(address pool, int24 lowerTick, int24 upperTick, uint128 liquidity) public view returns (uint amount0, uint amount1) {
        //slither-disable-next-line unused-return
        (uint160 sqrtRatioX96, , , , , ,) = IAlgebraPool(pool).globalState();
        (amount0, amount1) = UniswapV3MathLib.getAmountsForLiquidity(sqrtRatioX96, lowerTick, upperTick, liquidity);
    }

    /// @inheritdoc IDexAdapter
    function getProportion0(address pool) public view returns (uint) {
        address token1 = IAlgebraPool(pool).token1();
        //slither-disable-next-line unused-return
        (uint160 sqrtRatioX96, int24 tick,,,,,) = IAlgebraPool(pool).globalState();
        int24 tickSpacing = IAlgebraPool(pool).tickSpacing();
        (int24 lowerTick, int24 upperTick) = UniswapV3MathLib.getTicksInSpacing(tick, tickSpacing);
        uint token1Price = getPrice(pool, token1, address(0), 0);
        uint token1Decimals = IERC20Metadata(token1).decimals();
        uint token0Desired = token1Price;
        uint token1Desired = 10 ** token1Decimals;
        uint128 liquidityOut = UniswapV3MathLib.getLiquidityForAmounts(sqrtRatioX96, lowerTick, upperTick, token0Desired, token1Desired);
        (uint amount0Consumed, uint amount1Consumed) = UniswapV3MathLib.getAmountsForLiquidity(sqrtRatioX96, lowerTick, upperTick, liquidityOut);
        uint consumed1Priced = amount1Consumed * token1Price / token1Desired;
        return consumed1Priced * 1e18 / (amount0Consumed + consumed1Priced);
    }

    /// @inheritdoc IDexAdapter
    function getProportions(address pool) external view returns (uint[] memory) {
        uint[] memory p = new uint[](2);
        p[0] = getProportion0(pool);
        p[1] = 1e18 - p[0];
        return p;
    }

    /// @inheritdoc IDexAdapter
    function swap(
        address pool,
        address tokenIn,
        address tokenOut,
        address recipient,
        uint priceImpactTolerance
    ) external {
        address token0 = IAlgebraPool(pool).token0();

        uint balanceBefore = IERC20(tokenOut).balanceOf(recipient);
        uint amount = IERC20(tokenIn).balanceOf(address(this));

        {
            uint priceBefore = getPrice(pool, tokenIn, tokenOut, amount);

            //slither-disable-next-line unused-return
            IAlgebraPool(pool).swap(
                recipient,
                tokenIn == token0,
                int(amount),
                tokenIn == token0 ? UniswapV3MathLib.MIN_SQRT_RATIO : UniswapV3MathLib.MAX_SQRT_RATIO,
                abi.encode(SwapCallbackData(tokenIn, amount))
            );

            uint priceAfter = getPrice(pool, tokenIn, tokenOut, amount);
            // unreal but better to check
            require(priceAfter <= priceBefore, "Price increased");

            uint priceImpact = (priceBefore - priceAfter) * ConstantsLib.DENOMINATOR / priceBefore;
            require(priceImpact < priceImpactTolerance, string(abi.encodePacked("!PRICE ", Strings.toString(priceImpact))));
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

    /// @inheritdoc IDexAdapter
    function getPrice(
        address pool,
        address tokenIn,
        address /*tokenOut*/,
        uint amount
    ) public view returns (uint) {
        address token0 = IAlgebraPool(pool).token0();
        address token1 = IAlgebraPool(pool).token1();

        uint256 tokenInDecimals = tokenIn == token0 ? IERC20Metadata(token0).decimals() : IERC20Metadata(token1).decimals();
        uint256 tokenOutDecimals = tokenIn == token1 ? IERC20Metadata(token0).decimals() : IERC20Metadata(token1).decimals();
        //slither-disable-next-line unused-return
        (uint160 sqrtPriceX96,,,,,,) = IAlgebraPool(pool).globalState();

        uint divider = tokenOutDecimals < 18 ? UniswapV3MathLib._max(10 ** tokenOutDecimals / 10 ** tokenInDecimals, 1) : 1;

        uint priceDigits = UniswapV3MathLib._countDigits(uint(sqrtPriceX96));
        uint purePrice;
        uint precision;
        if (tokenIn == token0) {
            precision = 10 ** ((priceDigits < 29 ? 29 - priceDigits : 0) + tokenInDecimals);
            uint part = uint(sqrtPriceX96) * precision / UniswapV3MathLib.TWO_96;
            purePrice = part * part;
        } else {
            precision = 10 ** ((priceDigits > 29 ? priceDigits - 29 : 0) + tokenInDecimals);
            uint part = UniswapV3MathLib.TWO_96 * precision / uint(sqrtPriceX96);
            purePrice = part * part;
        }
        uint price = purePrice / divider / precision / (precision > 1e18 ? (precision / 1e18) : 1);

        if (amount != 0) {
            return price * amount / (10 ** tokenInDecimals);
        } else {
            return price;
        }
    }

    function algebraSwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata _data
    ) external {
        require(amount0Delta > 0 || amount1Delta > 0, "Wrong callback amount");
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        IERC20(data.tokenIn).safeTransfer(msg.sender, data.amount);
    }

    /// @inheritdoc IDexAdapter
    function DEX_ADAPTER_ID() external pure returns(string memory) {
        return _DEX_ADAPTER_ID;
    }
}
