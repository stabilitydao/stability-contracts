// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {AmmAdapterIdLib} from "./libs/AmmAdapterIdLib.sol";
import {ConstantsLib} from "../core/libs/ConstantsLib.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IPoolInfo} from "../integrations/balancerv3/IPoolInfo.sol";
import {IBalancerAdapter} from "../interfaces/IBalancerAdapter.sol";
import {IRouter} from "../integrations/balancerv3/IRouter.sol";
import {IStablePool} from "../integrations/balancerv3/IStablePool.sol";
import {Rounding} from "../integrations/balancerv3/VaultTypes.sol";
import {ScalingHelpers} from "./libs/balancerv3/ScalingHelpers.sol";
import {IBalancerPoolToken} from "../integrations/balancerv3/IBalancerPoolToken.sol";
import {IVaultExtension} from "../integrations/balancerv3/IVaultExtension.sol";
import {StableMath} from "./libs/balancerv3/StableMath.sol";
import {IPermit2} from "../integrations/permit2/IPermit2.sol";

/// @title AMM adapter for Balancer V3 stable pools
/// @author Alien Deployer (https://github.com/a17)
contract BalancerV3StableAdapter is Controllable, IAmmAdapter, IBalancerAdapter {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.BalancerV3StableAdapter")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant STORAGE_LOCATION = 0xdaeb8260b874aed93418395b99eeb6877f5241937db3fb4ff3b6122f2614df00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.BalancerV3StableAdapter
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
            require(minimalAmount != 0, "Too low amountIn");
            uint price = getPrice(pool, tokenIn, tokenOut, minimalAmount);
            amountOutMax = price * amountIn / minimalAmount;
        }

        IERC20(tokenIn).approve(PERMIT2, amountIn);
        IPermit2(PERMIT2).approve(tokenIn, router, uint160(amountIn), uint48(block.timestamp));

        uint amountOut = IRouter(router).swapSingleTokenExactIn(
            pool, IERC20(tokenIn), IERC20(tokenOut), amountIn, 0, block.timestamp, false, ""
        );

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
        return AmmAdapterIdLib.BALANCER_V3_STABLE;
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
        address pool,
        uint[] memory amounts
    ) external returns (uint liquidity, uint[] memory amountsConsumed) {
        amountsConsumed = amounts;
        AdapterStorage storage $ = _getStorage();
        liquidity = IRouter($.router).queryAddLiquidityUnbalanced(pool, amounts, address(this), "");
    }

    /// @inheritdoc IAmmAdapter
    function getProportions(address pool) external view returns (uint[] memory props) {
        (address[] memory tokens,, uint[] memory balances,) = IPoolInfo(pool).getTokenInfo();
        uint totalInAsset0;
        uint len = tokens.length;
        uint[] memory pricedBalances = new uint[](len);
        for (uint i; i < len; ++i) {
            uint tokenDecimals = IERC20Metadata(tokens[i]).decimals();
            uint price = i == 0
                ? 10 ** tokenDecimals
                : getPrice(pool, address(tokens[i]), address(tokens[0]), 10 ** (tokenDecimals - 3)) * 1000;
            pricedBalances[i] = balances[i] * price / 10 ** tokenDecimals;
            totalInAsset0 += pricedBalances[i];
        }
        props = new uint[](len);
        for (uint i; i < len; ++i) {
            props[i] = pricedBalances[i] * 1e18 / totalInAsset0;
        }
    }

    /// @inheritdoc IAmmAdapter
    function getPrice(address pool, address tokenIn, address tokenOut, uint amount) public view returns (uint) {
        address[] memory tokens = poolTokens(pool);
        uint[] memory balancesScaled18 = IPoolInfo(pool).getCurrentLiveBalances();
        (uint tokenInIndex, uint tokenOutIndex) = _getTokenInOutIndexes(tokens, tokenIn, tokenOut);
        (uint currentAmp,,) = IStablePool(pool).getAmplificationParameter();
        uint invariant = IStablePool(pool).computeInvariant(balancesScaled18, Rounding.ROUND_DOWN);
        address vault = IBalancerPoolToken(pool).getVault();
        (uint[] memory decimalScalingFactors, uint[] memory tokenRates) = IVaultExtension(vault).getPoolTokenRates(pool);
        uint amountGivenScaled18 = ScalingHelpers.toScaled18ApplyRateRoundDown(
            amount, decimalScalingFactors[tokenInIndex], tokenRates[tokenInIndex]
        );
        uint amountOutScaled18 = StableMath.computeOutGivenExactIn(
            currentAmp, balancesScaled18, tokenInIndex, tokenOutIndex, amountGivenScaled18, invariant
        );
        return ScalingHelpers.toRawUndoRateRoundDown(
            amountOutScaled18,
            decimalScalingFactors[tokenOutIndex],
            ScalingHelpers.computeRateRoundUp(tokenRates[tokenOutIndex])
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
