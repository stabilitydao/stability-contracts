// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {ConstantsLib} from "../core/libs/ConstantsLib.sol";
import {AmmAdapterIdLib} from "./libs/AmmAdapterIdLib.sol";
import {Errors} from "./libs/balancer/BalancerErrors.sol";
import {FixedPoint} from "./libs/balancer/FixedPoint.sol";
import {ScaleLib} from "./libs/balancer/ScaleLib.sol";
import {StableMath} from "./libs/balancer/StableMath.sol";
import {IBComposableStablePoolMinimal} from "../integrations/balancer/IBComposableStablePoolMinimal.sol";
import {IBVault, IAsset} from "../integrations/balancer/IBVault.sol";
import {IBalancerHelper, IVault} from "../integrations/balancer/IBalancerHelper.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IBalancerAdapter} from "../interfaces/IBalancerAdapter.sol";

/// @title AMM adapter for Balancer ComposableStable pools
/// @author Alien Deployer (https://github.com/a17)
contract BalancerComposableStableAdapter is Controllable, IAmmAdapter, IBalancerAdapter {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.BalancerComposableStableAdapter")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant STORAGE_LOCATION = 0x4235c883b69d0c060f4f9a2c87fa015d10166773b6a97be421a79340d62c1e00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct GetLiquidityForAmountsVars {
        bytes32 poolId;
        address[] assets;
        uint bptIndex;
        uint len;
    }

    struct GetProportionsVars {
        uint bptIndex;
        uint asset0Index;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.BalancerComposableStableAdapter
    struct AdapterStorage {
        address balancerHelpers;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function init(address platform_) external initializer {
        __Controllable_init(platform_);
    }

    /// @inheritdoc IBalancerAdapter
    function setupHelpers(address balancerHelpers) external {
        AdapterStorage storage $ = _getStorage();
        if ($.balancerHelpers != address(0)) {
            revert AlreadyExist();
        }
        $.balancerHelpers = balancerHelpers;
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

        address balancerVault = IBComposableStablePoolMinimal(pool).getVault();

        // Initializing each struct field one-by-one uses less gas than setting all at once.
        IBVault.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = false;
        funds.recipient = payable(recipient);
        funds.toInternalBalance = false;

        // Initializing each struct field one-by-one uses less gas than setting all at once.
        IBVault.SingleSwap memory singleSwap;
        singleSwap.poolId = IBComposableStablePoolMinimal(pool).getPoolId();
        singleSwap.kind = IBVault.SwapKind.GIVEN_IN;
        singleSwap.assetIn = IAsset(address(tokenIn));
        singleSwap.assetOut = IAsset(address(tokenOut));
        singleSwap.amount = amountIn;
        singleSwap.userData = "";

        // scope for checking price impact
        uint amountOutMax;
        {
            uint minimalAmount = amountIn / 1000;
            require(minimalAmount != 0, "Too low amountIn");
            uint price = getPrice(pool, tokenIn, tokenOut, minimalAmount);
            amountOutMax = price * amountIn / minimalAmount;
        }

        IERC20(tokenIn).approve(balancerVault, amountIn);
        uint amountOut = IBVault(balancerVault).swap(singleSwap, funds, 1, block.timestamp);

        uint priceImpact =
            amountOutMax < amountOut ? 0 : (amountOutMax - amountOut) * ConstantsLib.DENOMINATOR / amountOutMax;
        if (priceImpact > priceImpactTolerance) {
            revert(string(abi.encodePacked("!PRICE ", Strings.toString(priceImpact))));
        }

        emit SwapInPool(pool, tokenIn, tokenOut, recipient, priceImpactTolerance, amountIn, amountOut);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function ammAdapterId() external pure returns (string memory) {
        return AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE;
    }

    /// @inheritdoc IAmmAdapter
    function poolTokens(address pool) public view returns (address[] memory tokens) {
        IBComposableStablePoolMinimal _pool = IBComposableStablePoolMinimal(pool);
        (address[] memory bTokens,,) = IBVault(_pool.getVault()).getPoolTokens(_pool.getPoolId());
        uint bptIndex = _pool.getBptIndex();
        uint len = bTokens.length - 1;
        tokens = new address[](len);
        for (uint i; i < len; ++i) {
            tokens[i] = bTokens[i < bptIndex ? i : i + 1];
        }
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
        GetLiquidityForAmountsVars memory v;
        IBComposableStablePoolMinimal _pool = IBComposableStablePoolMinimal(pool);
        v.poolId = _pool.getPoolId();
        (v.assets,,) = IBVault(_pool.getVault()).getPoolTokens(v.poolId);
        v.len = v.assets.length;
        v.bptIndex = _pool.getBptIndex();
        uint k;
        uint[] memory amountsIn;
        (liquidity, amountsIn) = IBalancerHelper(_getStorage().balancerHelpers).queryJoin(
            v.poolId,
            address(this),
            address(this),
            IVault.JoinPoolRequest({
                assets: v.assets,
                maxAmountsIn: amounts,
                userData: abi.encode(IBVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amounts, 0),
                fromInternalBalance: false
            })
        );
        k = 0;
        amountsConsumed = new uint[](v.len - 1);
        for (uint i; i < v.len; ++i) {
            if (i != v.bptIndex) {
                amountsConsumed[k] = amountsIn[i];
                k++;
            }
        }
    }

    /// @inheritdoc IAmmAdapter
    function getProportions(address pool) external view returns (uint[] memory props) {
        GetProportionsVars memory v;
        IBComposableStablePoolMinimal _pool = IBComposableStablePoolMinimal(pool);
        v.bptIndex = _pool.getBptIndex();
        v.asset0Index = v.bptIndex == 0 ? 1 : 0;
        (address[] memory tokens, uint[] memory balances,) = IBVault(_pool.getVault()).getPoolTokens(_pool.getPoolId());
        uint totalInAsset0;
        uint len = tokens.length;
        uint[] memory pricedBalances = new uint[](len - 1);
        uint k;
        for (uint i; i < len; ++i) {
            if (i != v.bptIndex) {
                uint tokenDecimals = IERC20Metadata(tokens[i]).decimals();
                uint price = i == v.asset0Index
                    ? 10 ** tokenDecimals
                    : getPrice(pool, address(tokens[i]), address(tokens[v.asset0Index]), 10 ** (tokenDecimals - 3)) * 1000;
                pricedBalances[k] = balances[i] * price / 10 ** tokenDecimals;
                totalInAsset0 += pricedBalances[k];
                k++;
            }
        }
        props = new uint[](len - 1);
        for (uint i; i < len - 1; ++i) {
            props[i] = pricedBalances[i] * 1e18 / totalInAsset0;
        }
    }

    /// @inheritdoc IAmmAdapter
    function getPrice(address pool, address tokenIn, address tokenOut, uint amount) public view returns (uint) {
        IBComposableStablePoolMinimal _pool = IBComposableStablePoolMinimal(pool);
        {
            // take pool commission
            uint swapFeePercentage = _pool.getSwapFeePercentage();
            amount -= FixedPoint.mulUp(amount, swapFeePercentage);
        }
        bytes32 poolId = _pool.getPoolId();
        (address[] memory tokens, uint[] memory balances,) = IBVault(_pool.getVault()).getPoolTokens(poolId);

        uint tokenInIndex = type(uint).max;
        uint tokenOutIndex = type(uint).max;

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

        // require(tokenInIndex < len, 'Wrong tokenIn');
        // require(tokenOutIndex < len, 'Wrong tokenOut');

        uint[] memory scalingFactors = _pool.getScalingFactors();
        ScaleLib._upscaleArray(balances, scalingFactors);

        uint bptIndex = _pool.getBptIndex();
        balances = _dropBptItem(balances, bptIndex);

        uint upscaledAmount = ScaleLib._upscale(amount, scalingFactors[tokenInIndex]);

        tokenInIndex = _skipBptIndex(tokenInIndex, bptIndex);
        uint tokenOutIndexWoBpt = _skipBptIndex(tokenOutIndex, bptIndex);

        (uint currentAmp,,) = _pool.getAmplificationParameter();
        {
            uint invariant = StableMath._calculateInvariant(currentAmp, balances, false);

            uint amountOutUpscaled = StableMath._calcOutGivenIn(
                currentAmp, balances, tokenInIndex, tokenOutIndexWoBpt, upscaledAmount, invariant
            );
            return ScaleLib._downscaleDown(amountOutUpscaled, scalingFactors[tokenOutIndex]);
        }
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(Controllable, IERC165) returns (bool) {
        return interfaceId == type(IAmmAdapter).interfaceId || interfaceId == type(IBalancerAdapter).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _dropBptItem(uint[] memory amounts, uint bptIndex) internal pure returns (uint[] memory) {
        uint len = amounts.length - 1;
        uint[] memory amountsWithoutBpt = new uint[](len);
        for (uint i; i < len; ++i) {
            amountsWithoutBpt[i] = amounts[i < bptIndex ? i : i + 1];
        }

        return amountsWithoutBpt;
    }

    function _skipBptIndex(uint index, uint bptIndex) internal pure returns (uint) {
        return index < bptIndex ? index : index - 1;
    }

    function _getStorage() private pure returns (AdapterStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }
}
