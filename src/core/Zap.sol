// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./base/Controllable.sol";
import "./libs/ConstantsLib.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IZap.sol";

/// @title Implementation of ZAP feature in the Stability platform.
/// ZAP feature simplifies the DeFi investment process.
/// With ZAP users can provide liquidity to DeXs and liquidity mining/management vaults by single asset.
/// In this case, an asset is swapped for the pool assets in the required proportion.
/// The swap is carried out through one of the DeX aggregators allowed in the platform.
/// The platform architecture makes it possible to use ZAP for all created vaults.
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
contract Zap is Controllable, ReentrancyGuardUpgradeable, IZap {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.2";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
        __ReentrancyGuard_init();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IZap
    // slither-disable-next-line calls-loop
    function deposit(
        address vault,
        address tokenIn,
        uint amountIn,
        address agg,
        bytes[] memory swapData,
        uint minSharesOut,
        address receiver
    ) external nonReentrant {
        // todo check vault

        if (amountIn == 0) {
            revert IControllable.IncorrectZeroArgument();
        }

        if (!IPlatform(platform()).isAllowedDexAggregatorRouter(agg)) {
            revert NotAllowedDexAggregator(agg);
        }

        if (receiver == address(0)) {
            receiver = msg.sender;
        }

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        _approveIfNeeds(tokenIn, amountIn, agg);

        address strategy = address(IVault(vault).strategy());
        address[] memory assets = IStrategy(strategy).assets();
        uint len = assets.length;
        uint[] memory depositAmounts = new uint[](len);
        // nosemgrep
        for (uint i; i < len; ++i) {
            if (tokenIn == assets[i]) {
                continue;
            }
            //slither-disable-next-line low-level-calls
            (bool success, bytes memory result) = agg.call(swapData[i]);
            if (!success) {
                revert AggSwapFailed(string(result));
            }
        }
        // nosemgrep
        for (uint i; i < len; ++i) {
            // slither-disable-next-line calls-loop
            depositAmounts[i] = IERC20(assets[i]).balanceOf(address(this));
            _approveIfNeeds(assets[i], depositAmounts[i], vault);
        }

        IVault(vault).depositAssets(assets, depositAmounts, minSharesOut, receiver);

        _sendAllRemaining(tokenIn, assets, IStrategy(strategy).underlying());
    }

    /// @inheritdoc IZap
    // slither-disable-next-line calls-loop
    function withdraw(
        address vault,
        address tokenOut,
        address agg,
        bytes[] memory swapData,
        uint sharesToBurn,
        uint minAmountOut
    ) external nonReentrant {
        if (!IPlatform(platform()).isAllowedDexAggregatorRouter(agg)) {
            revert NotAllowedDexAggregator(agg);
        }

        uint len = swapData.length;
        address strategy = address(IVault(vault).strategy());
        address[] memory assets = IStrategy(strategy).assets();
        uint[] memory amountsOut =
            IVault(vault).withdrawAssets(assets, sharesToBurn, new uint[](len), address(this), msg.sender);
        // nosemgrep
        for (uint i; i < len; ++i) {
            if (tokenOut == assets[i]) {
                continue;
            }

            _approveIfNeeds(assets[i], amountsOut[i], agg);
            // slither-disable-next-line low-level-calls
            (bool success, bytes memory result) = agg.call(swapData[i]);
            if (!success) {
                revert AggSwapFailed(string(result));
            }
        }

        uint b = IERC20(tokenOut).balanceOf(address(this));
        if (b < minAmountOut) {
            revert Slippage(b, minAmountOut);
        }

        _sendAllRemaining(tokenOut, assets, IStrategy(strategy).underlying());
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IZap
    function getDepositSwapAmounts(
        address vault,
        address tokenIn,
        uint amountIn
    ) external view returns (address[] memory tokensOut, uint[] memory swapAmounts) {
        address strategy = address(IVault(vault).strategy());
        tokensOut = IStrategy(strategy).assets();
        uint len = tokensOut.length;
        swapAmounts = new uint[](len);
        uint[] memory proportions = IStrategy(strategy).getAssetsProportions();
        uint amountInUsed = 0;
        // nosemgrep
        for (uint i; i < len; ++i) {
            if (tokensOut[i] == tokenIn) {
                amountInUsed += amountIn * proportions[i] / 1e18;
                continue;
            }
            if (i < len - 1) {
                swapAmounts[i] = amountIn * proportions[i] / 1e18;
                amountInUsed += swapAmounts[i];
            } else {
                swapAmounts[i] = amountIn - amountInUsed;
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Make infinite approve of {token} to {spender} if the approved amount is less than {amount}
    /// @dev Should NOT be used for third-party pools
    function _approveIfNeeds(address token, uint amount, address spender) internal {
        // slither-disable-next-line calls-loop
        if (IERC20(token).allowance(address(this), spender) < amount) {
            IERC20(token).forceApprove(spender, type(uint).max);
        }
    }

    function _sendAllRemaining(address tokenIn, address[] memory strategyAssets, address underlying) internal {
        _sendRemaining(tokenIn);

        uint len = strategyAssets.length;
        // nosemgrep
        for (uint i; i < len; ++i) {
            _sendRemaining(strategyAssets[i]);
        }

        if (underlying != address(0)) {
            _sendRemaining(underlying);
        }
    }

    function _sendRemaining(address token) internal {
        uint bal = IERC20(token).balanceOf(address(this));
        if (bal > 0) {
            IERC20(token).safeTransfer(msg.sender, bal);
        }
    }
}
