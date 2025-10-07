// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AmmAdapterIdLib} from "./libs/AmmAdapterIdLib.sol";
import {ConstantsLib} from "../core/libs/ConstantsLib.sol";
import {Controllable, IControllable, IERC165} from "../core/base/Controllable.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";
import {IStakedBUSD} from "../integrations/brunch/IStakedBUSD.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AMM adapter for contracts inherited from StakedERC20 interface
/// Changelog:
/// @author dvpublic (https://github.com/dvpublic)
contract BrunchAdapter is Controllable, IAmmAdapter {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error IncorrectTokens();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function init(address platform_) external initializer {
        __Controllable_init(platform_);
    }

    //region ------------------------------------ User actions
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
        uint amount = IERC20(tokenIn).balanceOf(address(this));

        // slither-disable-next-line uninitialized-state
        uint amountOut;

        if (tokenIn == pool && tokenOut == IStakedBUSD(pool).underlyingAsset()) {
            // unstake asset from sbUSD
            uint minAmountOut = _getPrice(pool, tokenIn, tokenOut, amount, IStakedBUSD(pool).exchangeRateCurrent())
                * (ConstantsLib.DENOMINATOR - priceImpactTolerance) / ConstantsLib.DENOMINATOR;
            IStakedBUSD(pool).redeem(amount);

            amountOut = IERC20(tokenOut).balanceOf(address(this));
            IERC20(tokenOut).safeTransfer(recipient, amountOut);

            uint priceImpact =
                amountOut > minAmountOut ? 0 : (minAmountOut - amountOut) * ConstantsLib.DENOMINATOR / minAmountOut;
            if (priceImpact > priceImpactTolerance) {
                revert(string(abi.encodePacked("!PRICE ", Strings.toString(priceImpact))));
            }
        } else if (tokenOut == pool && tokenIn == IStakedBUSD(pool).underlyingAsset()) {
            IERC20(tokenIn).forceApprove(pool, amount);
            uint balanceBefore = IERC20(tokenOut).balanceOf(address(this));
            uint minAmountOut = _getPrice(pool, tokenIn, tokenOut, amount, IStakedBUSD(pool).exchangeRateCurrent())
                * (ConstantsLib.DENOMINATOR - priceImpactTolerance) / ConstantsLib.DENOMINATOR;

            IStakedBUSD(pool).mint(amount);
            amountOut = IERC20(tokenOut).balanceOf(address(this)) - balanceBefore;
            IERC20(tokenOut).safeTransfer(recipient, amountOut);

            uint priceImpact =
                amountOut > minAmountOut ? 0 : (minAmountOut - amountOut) * ConstantsLib.DENOMINATOR / minAmountOut;
            if (priceImpact > priceImpactTolerance) {
                revert(string(abi.encodePacked("!PRICE ", Strings.toString(priceImpact))));
            }
        } else {
            revert IncorrectTokens();
        }

        emit SwapInPool(pool, tokenIn, tokenOut, recipient, priceImpactTolerance, amount, amountOut);
    }
    //endregion ---------------------------------- User actions

    //region ------------------------------------ View functions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function ammAdapterId() external pure returns (string memory) {
        return AmmAdapterIdLib.BRUNCH;
    }

    /// @inheritdoc IAmmAdapter
    function poolTokens(address pool) public view returns (address[] memory tokens) {
        tokens = new address[](2);
        tokens[0] = pool;
        tokens[1] = IStakedBUSD(pool).underlyingAsset();
    }

    /// @inheritdoc IAmmAdapter
    function getLiquidityForAmounts(address, uint[] memory) external pure returns (uint, uint[] memory) {
        revert("Not supported");
    }

    /// @inheritdoc IAmmAdapter
    function getProportions(address) external pure returns (uint[] memory) {
        revert("Not supported");
    }

    /// @inheritdoc IAmmAdapter
    function getPrice(address pool, address tokenIn, address tokenOut, uint amount) public view returns (uint) {
        return _getPrice(pool, tokenIn, tokenOut, amount, IStakedBUSD(pool).exchangeRateStored());
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(Controllable, IERC165) returns (bool) {
        return interfaceId == type(IAmmAdapter).interfaceId || super.supportsInterface(interfaceId);
    }
    //endregion -------------------------------- View functions

    /// @notice Internal function to get price of tokenIn in tokenOut
    /// @param pool Address of the pool (staked-asset)
    /// @param tokenIn Address of the token to be sent to the pool (staked-asset or asset)
    /// @param tokenOut Address of the token to be received from the pool (asset or staked-asset)
    /// @param amount Amount of tokenIn to be sent to the pool (if 0 then 1.0 (10 ** decimals of tokenIn) will be used)
    /// @param exchangeRate Exchange rate of the pool (= underlying / staked-asset)
    /// @return price Price of tokenIn in tokenOut
    function _getPrice(
        address pool,
        address tokenIn,
        address tokenOut,
        uint amount,
        uint exchangeRate
    ) internal view returns (uint) {
        uint tokenInDecimals = IERC20Metadata(tokenIn).decimals();
        uint tokenOutDecimals = IERC20Metadata(tokenOut).decimals();

        // For zero value provided amount 1.0 (10 ** decimals of tokenIn) will be used.
        // slither-disable-next-line incorrect-equality
        if (amount == 0) {
            amount = 10 ** tokenInDecimals;
        }

        if (tokenIn == pool && tokenOut == IStakedBUSD(pool).underlyingAsset()) {
            return amount * exchangeRate / 1e18 * (10 ** tokenOutDecimals) / (10 ** tokenInDecimals);
        } else if (tokenOut == pool && tokenIn == IStakedBUSD(pool).underlyingAsset()) {
            return amount * 1e18 / exchangeRate * (10 ** tokenOutDecimals) / (10 ** tokenInDecimals);
        }

        revert IncorrectTokens();
    }
}
