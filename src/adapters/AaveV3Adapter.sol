// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {AmmAdapterIdLib} from "./libs/AmmAdapterIdLib.sol";
import {IPool} from "../integrations/aave/IPool.sol";
import {IAToken} from "../integrations/aave/IAToken.sol";

/// @title Adapter to wrap/unwrap AToken
/// @author omriss (https://github.com/omriss)
/// Changelog:
contract AaveV3Adapter is Controllable, IAmmAdapter {
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
    /// @dev pool is the AToken address
    function swap(
        address atoken,
        address tokenIn,
        address tokenOut,
        address recipient,
        uint priceImpactTolerance
    ) external {
        uint amountIn = IERC20(tokenIn).balanceOf(address(this));
        uint amountOut;

        IPool pool = IPool(IAToken(atoken).POOL());
        if (atoken == tokenIn) {
            amountOut = pool.withdraw(tokenOut, amountIn, recipient);
        } else {
            IERC20(tokenIn).forceApprove(address(pool), amountIn);
            pool.supply(tokenIn, amountIn, recipient, 0);
            // AToken is rebased token - 1:1, same decimals
            amountOut = amountIn;
        }

        emit SwapInPool(atoken, tokenIn, tokenOut, recipient, priceImpactTolerance, amountIn, amountOut);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function ammAdapterId() external pure returns (string memory) {
        return AmmAdapterIdLib.AAVE_V3;
    }

    /// @inheritdoc IAmmAdapter
    /// @dev pool is the AToken address
    function poolTokens(address pool) public view returns (address[] memory tokens) {
        tokens = new address[](2);
        tokens[0] = IAToken(pool).UNDERLYING_ASSET_ADDRESS();
        tokens[1] = pool;
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
    /// @dev pool is the AToken address
    function getPrice(
        address pool,
        address tokenIn,
        address tokenOut,
        uint amount
    ) public pure returns (uint) {
        return tokenIn == pool || tokenOut == pool
            // atoken is rebase token, so 1:1 price
            ? amount
            : 0;
    }

    /// @inheritdoc IAmmAdapter
    function getTwaPrice(
        address,
        /*pool*/
        address,
        /*tokenIn*/
        address,
        /*tokenOut*/
        uint,
        /*amount*/
        uint32 /*period*/
    ) external pure returns (uint) {
        revert("Not supported");
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(Controllable, IERC165) returns (bool) {
        return interfaceId == type(IAmmAdapter).interfaceId || super.supportsInterface(interfaceId);
    }
}
