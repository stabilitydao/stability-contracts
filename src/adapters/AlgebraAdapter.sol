// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../core/base/Controllable.sol";
import "../core/libs/ConstantsLib.sol";
import "../adapters/libs/AmmAdapterIdLib.sol";
import "../strategies/libs/UniswapV3MathLib.sol";
import "../interfaces/ICAmmAdapter.sol";
import "../integrations/algebra/IAlgebraPool.sol";

/// @notice AMM adapter for working with AlegbraV1 AMMs used in QuickSwapV3.
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
contract AlgebraAdapter is Controllable, ICAmmAdapter {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = '1.0.0';

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

    function algebraSwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata _data
    ) external {
        if(amount0Delta <= 0 && amount1Delta <= 0){
            revert IAmmAdapter.WrongCallbackAmount();
        }
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        IERC20(data.tokenIn).safeTransfer(msg.sender, data.amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
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
            if(priceAfter > priceBefore){
                revert IAmmAdapter.PriceIncreased();
            }

            uint priceImpact = (priceBefore - priceAfter) * ConstantsLib.DENOMINATOR / priceBefore;
            if(priceImpact >= priceImpactTolerance){
                revert (string(abi.encodePacked("!PRICE ", Strings.toString(priceImpact))));
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
    function ammAdapterId() external pure returns(string memory) {
        return AmmAdapterIdLib.ALGEBRA;
    }

    /// @inheritdoc IAmmAdapter
    function poolTokens(address pool) external view returns (address[] memory) {
        IAlgebraPool _pool = IAlgebraPool(pool);
        address[] memory tokens = new address[](2);
        tokens[0] = _pool.token0();
        tokens[1] = _pool.token1();
        return tokens;
    }

    /// @inheritdoc IAmmAdapter
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

        return UniswapV3MathLib.calcPriceOut(tokenIn, token0, sqrtPriceX96, tokenInDecimals, tokenOutDecimals, amount);
    }


    /// @inheritdoc IAmmAdapter
    function getLiquidityForAmounts(address, uint[] memory) external pure returns (uint, uint[] memory) {
        revert IAmmAdapter.NotSupportedByCAMM();
    }

        /// @inheritdoc IAmmAdapter
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

    /// @inheritdoc IAmmAdapter
    function getProportions(address pool) external view returns (uint[] memory) {
        uint[] memory p = new uint[](2);
        p[0] = getProportion0(pool);
        p[1] = 1e18 - p[0];
        return p;
    }

    /// @inheritdoc IAmmAdapter
    function getLiquidityForAmounts(address pool, uint[] memory amounts, int24[] memory ticks) external view returns (uint liquidity, uint[] memory amountsConsumed) {
        //slither-disable-next-line unused-return
        (uint160 sqrtRatioX96, , , , , ,) = IAlgebraPool(pool).globalState();
        uint128 liquidityOut = UniswapV3MathLib.getLiquidityForAmounts(sqrtRatioX96, ticks[0], ticks[1], amounts[0], amounts[1]);
        amountsConsumed = new uint[](2);
        (amountsConsumed[0], amountsConsumed[1]) = UniswapV3MathLib.getAmountsForLiquidity(sqrtRatioX96, ticks[0], ticks[1], liquidityOut);
        liquidity = uint(liquidityOut);
    }

    /// @inheritdoc IAmmAdapter
    function getAmountsForLiquidity(address pool, int24[] memory ticks, uint128 liquidity) external view returns (uint[] memory amounts) {
        amounts = new uint[](2);
        (amounts[0], amounts[1]) = _getAmountsForLiquidity(pool, ticks[0], ticks[1], liquidity);
    }

    /// @inheritdoc ICAmmAdapter
    function getPriceAtTick(
        address pool,
        address tokenIn,
        int24 tick
    ) external view returns (uint) {
        address token0 = IAlgebraPool(pool).token0();
        address token1 = IAlgebraPool(pool).token1();
        uint256 tokenInDecimals = tokenIn == token0 ? IERC20Metadata(token0).decimals() : IERC20Metadata(token1).decimals();
        uint256 tokenOutDecimals = tokenIn == token1 ? IERC20Metadata(token0).decimals() : IERC20Metadata(token1).decimals();
        uint160 sqrtPriceX96 = UniswapV3MathLib.getSqrtRatioAtTick(tick);
        return UniswapV3MathLib.calcPriceOut(tokenIn, token0, sqrtPriceX96, tokenInDecimals, tokenOutDecimals, 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getAmountsForLiquidity(address pool, int24 lowerTick, int24 upperTick, uint128 liquidity) internal view returns (uint amount0, uint amount1) {
        //slither-disable-next-line unused-return
        (uint160 sqrtRatioX96, , , , , ,) = IAlgebraPool(pool).globalState();
        (amount0, amount1) = UniswapV3MathLib.getAmountsForLiquidity(sqrtRatioX96, lowerTick, upperTick, liquidity);
    }
}
