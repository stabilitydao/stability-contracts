// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPermit2} from "../integrations/permit2/IPermit2.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AmmAdapterIdLib} from "./libs/AmmAdapterIdLib.sol";
import {Controllable, IControllable} from "../core/base/Controllable.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {IBalancerAdapter} from "../interfaces/IBalancerAdapter.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IPoolInfo} from "../integrations/balancerv3/IPoolInfo.sol";
import {IRouter} from "../integrations/balancerv3/IRouter.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ConstantsLib} from "../core/libs/ConstantsLib.sol";
import {ReClammPoolDynamicData, ReClammPoolImmutableData, IReClammPool} from "../integrations/reclamm/IReClammPool.sol";
import {ReClammMath, a, b} from "./libs/balancerv3/ReClammMath.sol";
import {ScalingHelpers} from "./libs/balancerv3/ScalingHelpers.sol";

/// @title AMM adapter for Balancer V3 ReCLAMM pools
/// @author Alien Deployer (https://github.com/a17)
contract BalancerV3ReClammAdapter is Controllable, IAmmAdapter, IBalancerAdapter {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.BalancerV3ReClammAdapter")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant STORAGE_LOCATION = 0x1e1f631b42f2fb77972646b67315696ad5ca38a298a2645a48cc79e667edc000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.BalancerV3ReClammAdapter
    struct AdapterStorage {
        address router;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function init(address platform_) external initializer {
        __Controllable_init(platform_);
    }

    /// @inheritdoc IBalancerAdapter
    function setupHelpers(address router) external {
        AdapterStorage storage $ = _getStorage();
        if ($.router != address(0)) {
            revert AlreadyExist();
        }
        $.router = router;
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

        AdapterStorage storage $ = _getStorage();
        address router = $.router;

        // scope for checking price impact
        uint amountOutMax;
        {
            uint minimalAmount = amountIn / 1000;
            require(minimalAmount != 0, TooLowAmountIn());

            uint price = getPrice(pool, tokenIn, tokenOut, minimalAmount);
            require(price != 0, TooLowAmountIn());

            amountOutMax = price * amountIn / minimalAmount;
        }

        IERC20(tokenIn).approve(PERMIT2, amountIn);
        IPermit2(PERMIT2).approve(tokenIn, router, uint160(amountIn), uint48(block.timestamp));

        uint amountOut = IRouter(router)
            .swapSingleTokenExactIn(pool, IERC20(tokenIn), IERC20(tokenOut), amountIn, 0, block.timestamp, false, "");

        uint priceImpact =
            amountOutMax < amountOut ? 0 : (amountOutMax - amountOut) * ConstantsLib.DENOMINATOR / amountOutMax;
        if (priceImpact > priceImpactTolerance) {
            revert(string(abi.encodePacked("!PRICE ", Strings.toString(priceImpact))));
        }

        IERC20(tokenOut).safeTransfer(recipient, amountOut);

        emit SwapInPool(pool, tokenIn, tokenOut, recipient, priceImpactTolerance, amountIn, amountOut);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function ammAdapterId() external pure returns (string memory) {
        return AmmAdapterIdLib.BALANCER_V3_RECLAMM;
    }

    /// @inheritdoc IAmmAdapter
    function poolTokens(address pool) public view returns (address[] memory tokens) {
        return IPoolInfo(pool).getTokens();
    }

    /// @inheritdoc IAmmAdapter
    function getLiquidityForAmounts(address, uint[] memory) external pure returns (uint, uint[] memory) {
        revert("Unavailable");
    }

    /// @inheritdoc IBalancerAdapter
    function getLiquidityForAmountsWrite(
        address, /*pool*/
        uint[] memory /*amounts*/
    )
        external
        pure
        returns (
            uint, /*liquidity*/
            uint[] memory /*amountsConsumed*/
        )
    {
        revert("Unavailable");
    }

    /// @inheritdoc IAmmAdapter
    function getProportions(address pool) external view returns (uint[] memory props) {
        ReClammPoolDynamicData memory data = IReClammPool(pool).getReClammPoolDynamicData();
        address[] memory tokens = poolTokens(pool);

        uint total; // scaled 18
        uint len = tokens.length;
        uint[] memory pricedBalances = new uint[](len);

        for (uint i; i < len; ++i) {
            uint price = i == 0
                ? 1e18
                // amount of token i in terms of token 0
                : ReClammMath.computeOutGivenIn(
                    data.balancesLiveScaled18, data.lastVirtualBalances[0], data.lastVirtualBalances[1], i, 0, 1e18
                );
            pricedBalances[i] = data.balancesLiveScaled18[i] * price / 1e18;
            total += pricedBalances[i];
        }

        props = new uint[](len);
        for (uint i; i < len; ++i) {
            props[i] = pricedBalances[i] * 1e18 / total;
        }
    }

    /// @inheritdoc IAmmAdapter
    function getPrice(address pool, address tokenIn, address tokenOut, uint amount) public view returns (uint) {
        ReClammPoolDynamicData memory dynData = IReClammPool(pool).getReClammPoolDynamicData();
        ReClammPoolImmutableData memory imData = IReClammPool(pool).getReClammPoolImmutableData();
        {
            // take pool commission into account
            uint swapFeePercentage = dynData.staticSwapFeePercentage;
            amount -= amount * swapFeePercentage / 1e18;
        }

        address[] memory tokens = poolTokens(pool);

        uint[] memory balancesScaled18 = dynData.balancesLiveScaled18;
        (uint tokenInIndex, uint tokenOutIndex) = _getTokenInOutIndexes(tokens, tokenIn, tokenOut);

        uint amountInScaled18 = ScalingHelpers.toScaled18ApplyRateRoundDown(
            amount, imData.decimalScalingFactors[tokenInIndex], dynData.tokenRates[tokenInIndex]
        );

        uint amountOutScaled18 = ReClammMath.computeOutGivenIn(
            balancesScaled18,
            dynData.lastVirtualBalances[a],
            dynData.lastVirtualBalances[b],
            tokenInIndex,
            tokenOutIndex,
            amountInScaled18
        );

        return ScalingHelpers.toRawUndoRateRoundDown(
            amountOutScaled18,
            imData.decimalScalingFactors[tokenOutIndex],
            ScalingHelpers.computeRateRoundUp(dynData.tokenRates[tokenOutIndex])
        );
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(Controllable, IERC165) returns (bool) {
        return interfaceId == type(IAmmAdapter).interfaceId || interfaceId == type(IBalancerAdapter).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getTokenInOutIndexes(
        address[] memory tokens,
        address tokenIn,
        address tokenOut
    ) internal pure returns (uint tokenInIndex, uint tokenOutIndex) {
        uint len = tokens.length;
        for (uint i; i < len; ++i) {
            if (tokens[i] == tokenIn) {
                tokenInIndex = i;
                break;
            }
        }
        for (uint i; i < len; ++i) {
            if (tokens[i] == tokenOut) {
                tokenOutIndex = i;
                break;
            }
        }
    }

    function _getStorage() private pure returns (AdapterStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }
}
