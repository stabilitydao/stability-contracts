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
import {WeightedMath} from "./libs/balancer/WeightedMath.sol";
import {IBVault, IAsset} from "../integrations/balancer/IBVault.sol";
import {IBalancerHelper, IVault} from "../integrations/balancer/IBalancerHelper.sol";
import {IBWeightedPoolMinimal} from "../integrations/balancer/IBWeightedPoolMinimal.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IBalancerAdapter} from "../interfaces/IBalancerAdapter.sol";

/// @title AMM adapter for Balancer Weighted pools
/// @author Alien Deployer (https://github.com/a17)
contract BalancerWeightedAdapter is Controllable, IAmmAdapter, IBalancerAdapter {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.BalancerWeightedAdapter")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant STORAGE_LOCATION = 0xa4f6828e593c072b951693fc34ca2cd3971b69396d7ba6ed5b73febddd360b00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.BalancerWeightedAdapter
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

        address balancerVault = IBWeightedPoolMinimal(pool).getVault();

        // Initializing each struct field one-by-one uses less gas than setting all at once.
        IBVault.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = false;
        funds.recipient = payable(recipient);
        funds.toInternalBalance = false;

        // Initializing each struct field one-by-one uses less gas than setting all at once.
        IBVault.SingleSwap memory singleSwap;
        singleSwap.poolId = IBWeightedPoolMinimal(pool).getPoolId();
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
        return AmmAdapterIdLib.BALANCER_WEIGHTED;
    }

    /// @inheritdoc IAmmAdapter
    function poolTokens(address pool) public view returns (address[] memory tokens) {
        IBWeightedPoolMinimal _pool = IBWeightedPoolMinimal(pool);
        (tokens,,) = IBVault(_pool.getVault()).getPoolTokens(_pool.getPoolId());
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
        address[] memory assets = poolTokens(pool);
        (liquidity, amountsConsumed) = IBalancerHelper(_getStorage().balancerHelpers).queryJoin(
            IBWeightedPoolMinimal(pool).getPoolId(),
            address(this),
            address(this),
            IVault.JoinPoolRequest({
                assets: assets,
                maxAmountsIn: amounts,
                userData: abi.encode(IBVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amounts, 0),
                fromInternalBalance: false
            })
        );
    }

    /// @inheritdoc IAmmAdapter
    function getProportions(address pool) external view returns (uint[] memory props) {
        props = IBWeightedPoolMinimal(pool).getNormalizedWeights();
    }

    /// @inheritdoc IAmmAdapter
    function getPrice(address pool, address tokenIn, address tokenOut, uint amount) public view returns (uint) {
        {
            // take pool commission
            uint swapFeePercentage = IBWeightedPoolMinimal(pool).getSwapFeePercentage();
            amount -= amount * swapFeePercentage / 10 ** 18;
        }
        address balancerVault = IBWeightedPoolMinimal(pool).getVault();
        bytes32 poolId = IBWeightedPoolMinimal(pool).getPoolId();
        (address[] memory tokens, uint[] memory balances,) = IBVault(balancerVault).getPoolTokens(poolId);

        uint[] memory weights = IBWeightedPoolMinimal(pool).getNormalizedWeights();

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

        return WeightedMath._calcOutGivenIn(
            balances[tokenInIndex], weights[tokenInIndex], balances[tokenOutIndex], weights[tokenOutIndex], amount
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

    function _getStorage() private pure returns (AdapterStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }
}
