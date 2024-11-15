// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {AmmAdapterIdLib} from "./libs/AmmAdapterIdLib.sol";
import {ISolidlyPool} from "../integrations/solidly/ISolidlyPool.sol";
import {ConstantsLib} from "../core/libs/ConstantsLib.sol";

/// @title AMM adapter for Solidly forks
/// @author Alien Deployer (https://github.com/a17)
contract SolidlyAdapter is Controllable, IAmmAdapter {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function init(address platform_) external initializer {
        __Controllable_init(platform_);
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
        uint amountIn = IERC20(tokenIn).balanceOf(address(this));
        uint amountOut = ISolidlyPool(pool).getAmountOut(amountIn, tokenIn);
        uint balanceBefore = IERC20(tokenOut).balanceOf(recipient);

        uint amount1 = 10 ** IERC20Metadata(tokenIn).decimals();
        uint priceBefore = getPrice(pool, tokenIn, tokenOut, amount1);

        uint amount0Out;
        uint amount1Out;
        {
            (address token0,) = _sortTokens(tokenIn, tokenOut);
            (amount0Out, amount1Out) = tokenIn == token0 ? (uint(0), amountOut) : (amountOut, uint(0));

            IERC20(tokenIn).safeTransfer(pool, amountIn);
        }
        ISolidlyPool(pool).swap(amount0Out, amount1Out, recipient, new bytes(0));

        uint priceAfter = getPrice(pool, tokenIn, tokenOut, amount1);
        uint priceImpact = (priceBefore - priceAfter) * ConstantsLib.DENOMINATOR / priceBefore;
        if (priceImpact >= priceImpactTolerance) {
            revert(string(abi.encodePacked("!PRICE ", Strings.toString(priceImpact))));
        }

        uint balanceAfter = IERC20(tokenOut).balanceOf(recipient);
        emit SwapInPool(
            pool,
            tokenIn,
            tokenOut,
            recipient,
            priceImpactTolerance,
            amountIn,
            balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function ammAdapterId() external pure returns (string memory) {
        return AmmAdapterIdLib.SOLIDLY;
    }

    /// @inheritdoc IAmmAdapter
    function poolTokens(address pool) public view returns (address[] memory tokens) {
        tokens = new address[](2);
        tokens[0] = ISolidlyPool(pool).token0();
        tokens[1] = ISolidlyPool(pool).token1();
    }

    /// @inheritdoc IAmmAdapter
    function getLiquidityForAmounts(
        address pool,
        uint[] memory amounts
    ) external view returns (uint liquidity, uint[] memory amountsConsumed) {
        amountsConsumed = new uint[](2);
        (uint reserveA, uint reserveB) = _getReserves(pool);
        uint amountBOptimal = _quoteAddLiquidity(amounts[0], reserveA, reserveB);
        if (amountBOptimal <= amounts[1]) {
            (amountsConsumed[0], amountsConsumed[1]) = (amounts[0], amountBOptimal);
        } else {
            uint amountAOptimal = _quoteAddLiquidity(amounts[1], reserveB, reserveA);
            (amountsConsumed[0], amountsConsumed[1]) = (amountAOptimal, amounts[1]);
        }

        uint _totalSupply = ISolidlyPool(pool).totalSupply();
        liquidity = Math.min(amountsConsumed[0] * _totalSupply / reserveA, amountsConsumed[1] * _totalSupply / reserveB);
    }

    /// @inheritdoc IAmmAdapter
    function getProportions(address pool) external view returns (uint[] memory props) {
        props = new uint[](2);
        if (ISolidlyPool(pool).stable()) {
            address token1 = ISolidlyPool(pool).token1();
            uint token1Decimals = IERC20Metadata(token1).decimals();
            uint token1Price = getPrice(pool, token1, address(0), 10 ** token1Decimals);
            (uint reserve0, uint reserve1) = _getReserves(pool);
            uint reserve1Priced = reserve1 * token1Price / 10 ** token1Decimals;
            uint totalPriced = reserve0 + reserve1Priced;
            props[0] = reserve0 * 1e18 / totalPriced;
            props[1] = reserve1Priced * 1e18 / totalPriced;
        } else {
            props[0] = 5e17;
            props[1] = 5e17;
        }
    }

    /// @inheritdoc IAmmAdapter
    function getPrice(address pool, address tokenIn, address, /*tokenOut*/ uint amount) public view returns (uint) {
        return ISolidlyPool(pool).getAmountOut(amount, tokenIn);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(Controllable, IERC165) returns (bool) {
        return interfaceId == type(IAmmAdapter).interfaceId || super.supportsInterface(interfaceId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns sorted token addresses, used to handle return values from pairs sorted in this order
    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function _getReserves(address pool) internal view returns (uint reserveA, uint reserveB) {
        address[] memory tokens = poolTokens(pool);
        (address token0,) = _sortTokens(tokens[0], tokens[1]);
        (uint reserve0, uint reserve1,) = ISolidlyPool(pool).getReserves();
        (reserveA, reserveB) = tokens[0] == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function _quoteAddLiquidity(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint) {
        return amountA * reserveB / reserveA;
    }
}
