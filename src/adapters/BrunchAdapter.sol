// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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

        if (tokenIn == pool) {

            // unstake asset from sbUSD

            // slither-disable-next-line unused-return
            IStakedBUSD(pool).redeem(amount);

            amountOut = IERC20(tokenOut).balanceOf(address(this));
            IERC20(tokenOut).safeTransfer(recipient, amountOut);
            // todo price impact
        } else if (tokenOut == pool) {
            IERC20(tokenIn).forceApprove(pool, amount);
            uint balanceBefore = IERC20(tokenOut).balanceOf(recipient);
            IStakedBUSD(pool).mint(amount);
            amountOut = IERC20(tokenOut).balanceOf(recipient) - balanceBefore;
            // todo price impact
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
        return AmmAdapterIdLib.STAKED_ERC20;
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
        uint tokenInDecimals = IERC20Metadata(tokenIn).decimals();
        uint tokenOutDecimals = IERC20Metadata(tokenOut).decimals();

        // For zero value provided amount 1.0 (10 ** decimals of tokenIn) will be used.
        // slither-disable-next-line incorrect-equality
        if (amount == 0) {
            amount = 10 ** tokenInDecimals;
        }

        // get exchange rate of staked-asset to asset
        // slither-disable-next-line unused-return
        uint exchangeRate = IStakedBUSD(pool).exchangeRateStored();

        if (tokenIn == pool) {

            // get price of tokenOut in USD
            // slither-disable-next-line unused-return
            (uint priceTokenOut,) = IPriceReader(IPlatform(platform()).priceReader()).getPrice(tokenOut);

            // staked-asset to asset
            // todo
            return amount * (10 ** tokenOutDecimals) * exchangeRate / priceTokenOut / (10 ** tokenInDecimals);
        } else if (tokenOut == pool) {
            // slither-disable-next-line unused-return
            (uint priceTokenIn,) = IPriceReader(IPlatform(platform()).priceReader()).getPrice(tokenIn);

            // Asset to staked-asset
            // todo
            return amount * (10 ** tokenOutDecimals) * priceTokenIn * exchangeRate / (10 ** tokenInDecimals) / 1e18;
        }

        revert IncorrectTokens();
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(Controllable, IERC165) returns (bool) {
        return interfaceId == type(IAmmAdapter).interfaceId || super.supportsInterface(interfaceId);
    }
    //endregion -------------------------------- View functions

}
