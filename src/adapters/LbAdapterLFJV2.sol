// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AmmAdapterIdLib} from "./libs/AmmAdapterIdLib.sol";
import {ConstantsLib} from "../core/libs/ConstantsLib.sol";
import {Controllable, IControllable, IERC165} from "../core/base/Controllable.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILbPairV2} from "../integrations/lblfgv2/ILbPairV2.sol";
import {IERC20Metadata} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Adapter for Liquidity Book (DLMM) as implemented by LFJ, see https://github.com/lfj-gg
/// @author omriss (https://github.com/omriss)
contract LbAdapterLFJV2 is Controllable, IAmmAdapter {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    error IncorrectTokens();
    error InsufficientOutputAmount(uint amountInLeft);

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
        ILbPairV2 pair = ILbPairV2(pool);

        // --------------- token-out balance before swap (to calculate actual amountOut after swap)
        uint balanceBefore = IERC20(tokenOut).balanceOf(recipient);

        // --------------- verify that provided tokens are correct
        address tokenX = pair.getTokenX();
        require(_isValid(pair, tokenIn, tokenOut, tokenX), IncorrectTokens());

        // --------------- input amount should be sent on balance of the pair contract before swap call
        uint amount = IERC20(tokenIn).balanceOf(address(this));
        IERC20(tokenIn).safeTransfer(pool, amount);

        // --------------- ensure that there is enough output amount in the pair
        (uint128 amountInLeft, uint128 price,) = pair.getSwapOut(uint128(amount), tokenIn == tokenX);
        require(amountInLeft == 0, InsufficientOutputAmount(amountInLeft));

        // --------------- perform the swap
        pair.swap(tokenX == tokenIn, recipient);

        // --------------- actual amount out received by the recipient
        uint balanceAfter = IERC20(tokenOut).balanceOf(recipient);
        uint amountOut = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;

        // --------------- verify that price impact is within the tolerance limit
        uint priceImpact = (price - amountOut) * ConstantsLib.DENOMINATOR / price;
        if (priceImpact >= priceImpactTolerance) {
            revert(string(abi.encodePacked("!PRICE ", Strings.toString(priceImpact))));
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
        return AmmAdapterIdLib.LBLFJ_V2;
    }

    /// @inheritdoc IAmmAdapter
    function poolTokens(address pool) public view returns (address[] memory tokens) {
        tokens = new address[](2);
        tokens[0] = ILbPairV2(pool).getTokenX();
        tokens[1] = ILbPairV2(pool).getTokenY();
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
    function getPrice(address pool, address tokenIn, address tokenOut, uint amount) public view returns (uint price) {
        address tokenX = ILbPairV2(pool).getTokenX();
        if (_isValid(ILbPairV2(pool), tokenIn, tokenOut, tokenX)) {
            if (amount == 0) {
                amount = 10 ** IERC20Metadata(tokenIn).decimals();
            }
            (uint128 amountInLeft, uint128 amountOut,) = ILbPairV2(pool).getSwapOut(uint128(amount), tokenIn == tokenX);

            // todo how to handle following case without reverting?
            require(amountInLeft == 0, InsufficientOutputAmount(amountInLeft));

            price = amountOut;
        }

        return price;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(Controllable, IERC165) returns (bool) {
        return interfaceId == type(IAmmAdapter).interfaceId || super.supportsInterface(interfaceId);
    }

    //endregion -------------------------------- View functions

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

    function _isValid(ILbPairV2 pair, address tokenIn, address tokenOut, address tokenX) internal view returns (bool) {
        address tokenY = pair.getTokenY();
        return (tokenX == tokenIn && tokenY == tokenOut) || (tokenY == tokenIn && tokenX == tokenOut);
    }
}
