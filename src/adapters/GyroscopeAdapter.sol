// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../core/libs/ConstantsLib.sol";
import "../core/base/Controllable.sol";
import "../adapters/libs/AmmAdapterIdLib.sol";
import "../interfaces/IAmmAdapter.sol";
import "../interfaces/IGyroECLPPool.sol";
import "../interfaces/IBVault.sol";
import "../interfaces/IBWeightedPoolMinimal.sol";
import "./libs/GyroECLPMath.sol";

/// @title AMM adapter for GyroECLP pools
/// @author Jude (https://github.com/iammrjude)
contract GyroscopeAdapter is Controllable, IAmmAdapter {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    address public constant balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    uint private constant _LIMIT = 1;

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
        uint amountOut = IBVault(balancerVault).swap(singleSwap, funds, _LIMIT, block.timestamp);

        require(
            amountOutMax < amountOut
                || (amountOutMax - amountOut) * ConstantsLib.DENOMINATOR / amountOutMax <= priceImpactTolerance,
            "!PRICE"
        );

        emit SwapInPool(pool, tokenIn, tokenOut, recipient, priceImpactTolerance, amountIn, amountOut);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function ammAdapterId() external pure returns (string memory) {
        return AmmAdapterIdLib.GYROSCOPE;
    }

    /// @inheritdoc IAmmAdapter
    function poolTokens(address pool) public view returns (address[] memory) {
        bytes32 poolId = IBWeightedPoolMinimal(pool).getPoolId();
        (IERC20[] memory tokenContracts,,) = IBVault(balancerVault).getPoolTokens(poolId);
        address[] memory tokens = new address[](tokenContracts.length);
        for (uint i; i < tokenContracts.length; ++i) {
            tokens[i] = address(tokenContracts[i]);
        }
        return tokens;
    }

    /// @inheritdoc IAmmAdapter
    function getLiquidityForAmounts(
        address pool,
        uint[] memory amounts
    ) external view returns (uint liquidity, uint[] memory amountsConsumed) {}

    /// @inheritdoc IAmmAdapter
    function getProportions(address pool) external view returns (uint[] memory props) {}

    /// @inheritdoc IAmmAdapter
    function getPrice(address pool, address tokenIn, address tokenOut, uint amount) public view returns (uint) {
        // return IGyroECLPPool(pool).getPrice();

        bytes32 poolId = IBWeightedPoolMinimal(pool).getPoolId();
        (IERC20[] memory tokens, uint[] memory balances,) = IBVault(balancerVault).getPoolTokens(poolId);

        bool tokenInIsToken0 = tokenIn == address(tokens[0]);
        (GyroECLPMath.Params memory eclpParams, GyroECLPMath.DerivedParams memory derivedECLPParams) =
            IGyroECLPPool(pool).getECLPParams();
        GyroECLPMath.Vector2 memory invariant;
        {
            (int currentInvariant, int invErr) =
                GyroECLPMath.calculateInvariantWithError(balances, eclpParams, derivedECLPParams);
            // invariant = overestimate in x-component, underestimate in y-component
            // No overflow in `+` due to constraints to the different values enforced in GyroECLPMath.
            invariant = GyroECLPMath.Vector2(currentInvariant + 2 * invErr, currentInvariant);
        }

        return GyroECLPMath.calcOutGivenIn(balances, amount, tokenInIsToken0, eclpParams, derivedECLPParams, invariant);
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
