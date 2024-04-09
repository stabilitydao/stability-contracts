// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../core/libs/ConstantsLib.sol";
import "../core/base/Controllable.sol";
import "../adapters/libs/AmmAdapterIdLib.sol";
import "../interfaces/IAmmAdapter.sol";
import "../integrations/curve/IStableSwapNG.sol";
import "../integrations/curve/IStableSwapNGPool.sol";
import "../integrations/curve/IStableSwapViews.sol";

/// @title AMM adapter for Curve StableSwap-NG pools with 2-8 tokens
/// @dev AMM source code https://github.com/curvefi/stableswap-ng/blob/main/contracts/main/CurveStableSwapNG.vy
/// @author Alien Deployer (https://github.com/a17)
contract CurveAdapter is Controllable, IAmmAdapter {
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
        (int128 tokenInIndex, int128 tokenOutIndex) = _getTokensIndexes(pool, tokenIn, tokenOut);
        uint amount = IERC20(tokenIn).balanceOf(address(this));
        uint balanceBefore = IERC20(tokenOut).balanceOf(recipient);
        {
            uint amount1 = 10 ** IERC20Metadata(tokenIn).decimals();
            uint priceBefore = getPrice(pool, tokenIn, tokenOut, amount1);
            _approveIfNeeded(tokenIn, amount, pool);
            // slither-disable-next-line unused-return
            IStableSwapNGPool(pool).exchange(tokenInIndex, tokenOutIndex, amount, 0, recipient);
            uint priceAfter = getPrice(pool, tokenIn, tokenOut, amount1);
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
        return AmmAdapterIdLib.CURVE;
    }

    /// @inheritdoc IAmmAdapter
    function poolTokens(address pool) public view returns (address[] memory tokens) {
        uint nCoins = IStableSwapNG(pool).N_COINS();
        tokens = new address[](nCoins);
        for (uint i; i < nCoins; ++i) {
            // slither-disable-next-line calls-loop
            tokens[i] = IStableSwapNGPool(pool).coins(i);
        }
    }

    /// @inheritdoc IAmmAdapter
    function getLiquidityForAmounts(
        address pool,
        uint[] memory amounts
    ) external view returns (uint liquidity, uint[] memory amountsConsumed) {
        liquidity = IStableSwapViews(pool).calc_token_amount(amounts, true);
        amountsConsumed = amounts;
    }

    /// @inheritdoc IAmmAdapter
    function getProportions(address pool) external view returns (uint[] memory props) {
        uint[] memory balances = IStableSwapNG(pool).get_balances();
        uint len = balances.length;
        uint[] memory valuedBalances = new uint[](len);
        valuedBalances[0] = balances[0];
        uint total = valuedBalances[0];
        for (uint i = 1; i < len; ++i) {
            // slither-disable-next-line calls-loop
            address tokenI = IStableSwapNGPool(pool).coins(i);
            // slither-disable-next-line calls-loop
            uint decimalsI = IERC20Metadata(tokenI).decimals();
            // slither-disable-next-line calls-loop
            uint priceI = IStableSwapNG(pool).get_dy(int128(uint128(i)), 0, 10 ** decimalsI);
            valuedBalances[i] = balances[i] * priceI / 10 ** decimalsI;
            total += valuedBalances[i];
        }
        props = new uint[](len);
        for (uint i; i < len; ++i) {
            props[i] = 1e18 * valuedBalances[i] / total;
        }
    }

    /// @inheritdoc IAmmAdapter
    function getPrice(address pool, address tokenIn, address tokenOut, uint amount) public view returns (uint) {
        (int128 tokenInIndex, int128 tokenOutIndex) = _getTokensIndexes(pool, tokenIn, tokenOut);
        return IStableSwapNG(pool).get_dy(tokenInIndex, tokenOutIndex, amount);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(Controllable, IERC165) returns (bool) {
        return interfaceId == type(IAmmAdapter).interfaceId || super.supportsInterface(interfaceId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getTokensIndexes(
        address pool,
        address tokenIn,
        address tokenOut
    ) internal view returns (int128 tokenInIndex, int128 tokenOutIndex) {
        address[] memory tokens = poolTokens(pool);
        uint len = tokens.length;
        for (uint i; i < len; ++i) {
            if (tokenIn == tokens[i]) {
                tokenInIndex = int128(uint128(i));
            }
            if (tokenOut == tokens[i]) {
                tokenOutIndex = int128(uint128(i));
            }
        }
    }

    /// @notice Make infinite approve of {token} to {spender} if the approved amount is less than {amount}
    /// @dev Should NOT be used for third-party pools
    function _approveIfNeeded(address token, uint amount, address spender) internal {
        if (IERC20(token).allowance(address(this), spender) < amount) {
            // infinite approve, 2*255 is more gas efficient then type(uint).max
            IERC20(token).forceApprove(spender, 2 ** 255);
        }
    }
}
