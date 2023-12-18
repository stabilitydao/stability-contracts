// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./StrategyBase.sol";
import "../../interfaces/IActiveStrategy.sol";
import '../../UniswapV3/IUniswapV3SwapRouter.sol';
import '../../UniswapV3/IUniswapV3Pool.sol';

abstract contract ActiveStrategyBase is StrategyBase, IActiveStrategy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    address private _uniswapRouterAddress;
    address private _tokenAddress;
    uint private _targetPercentage;
    uint private _thresholdPercentage;

    /// @dev Version of FarmingStrategyBase implementation
    string public constant VERSION_ACTIVE_STRATEGY_BASE = "0.1.0";

    /// @inheritdoc IActiveStrategy
    function rebalanceWithSwap(
        address[] memory,
        address[] memory,
        uint[] memory,
        bytes[] memory,
        address
    ) external virtual {
        revert NotSupported();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(StrategyBase) returns (bool) {
        return interfaceId == type(IActiveStrategy).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IActiveStrategy
    function needRebalance() external view returns (bool) {
        return _needRebalance();
    }

    /// @inheritdoc IActiveStrategy
    function needRebalanceWithSwap()
        external
        view
        virtual
        returns (bool, address[] memory, address[] memory, uint[] memory)
    {
        revert NotSupported();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIRTUAL LOGIC                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _needRebalance() internal view virtual returns (bool);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     OVERRIDEN LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _beforeDeposit() internal virtual override {
        if (_needRebalance()) {
            revert NeedRebalance();
        }
    }

    /// @inheritdoc StrategyBase
    function _beforeWithdraw() internal virtual override {
        if (_needRebalance()) {
            revert NeedRebalance();
        }
    }

    /// @inheritdoc StrategyBase
    function _beforeDoHardWork() internal virtual override {
        if (_needRebalance()) {
            revert NeedRebalance();
        }
    }

    function rebalance() external override {
        address tokenAddress = _tokenAddress;
        uint targetPercentage = _targetPercentage;
        uint thresholdPercentage = _thresholdPercentage;
        
        address uniswapRouterAddress = _uniswapRouterAddress;
        IUniswapV3SwapRouter router = IUniswapV3SwapRouter(uniswapRouterAddress);

        // Get the current token balance
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));

        // Calculate the target balance
        uint256 targetBalance = (balance * targetPercentage) / 100;
        
        // If the balance is below the threshold, increase the position
        if (balance < targetBalance) {
            // Calculate the amount to swap
            uint256 amountIn = targetBalance - balance;
            
            // Set the swap path (e.g., token -> ETH)
            address[] memory path = new address[](2);
            path[0] = tokenAddress;
            path[1] = router.WETH9();

            // Perform the swap
            uint256[] memory amounts = router.swapExactTokensForETH(
                amountIn,
                0,
                path,
                address(this),
                block.timestamp
            );
            
            // Add liquidity to the Uniswap V3 pool
            IUniswapV3Pool pool = IUniswapV3Pool(Math.sqrt(router.exactInputSingle(
                IUniswapV3SwapRouter.ExactInputSingleParams({
                    tokenIn: address(router.WETH9()),
                    tokenOut: tokenAddress,
                    fee: 3000,
                    recipient: address(this),
                    deadline: block.timestamp + 600,
                    amountIn: amounts[1],
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            )) * 2 ** 96);
            
            // Mint liquidity
            uint256 liquidity = pool.mint(
                address(this),
                amounts[1],
                0
            );
            
            // Do something with the liquidity tokens if needed
            
        } else if (balance > targetBalance + thresholdPercentage) {
            // Calculate the amount to swap
            uint256 amountOut = balance - targetBalance;
            
            // Set the swap path (e.g., ETH -> token)
            address[] memory path = new address[](2);
            path[0] = router.WETH9();
            path[1] = tokenAddress;
            
            // Perform the swap
            uint256[] memory amounts = router.swapExactETHForTokens{value: amountOut}(
                0,
                path,
                address(this),
                block.timestamp
            );
            
            // Remove liquidity from the Uniswap V3 pool
            IUniswapV3Pool pool = IUniswapV3Pool(router.exactOutputSingle(
                IUniswapV3SwapRouter.ExactOutputSingleParams({
                    tokenIn: tokenAddress,
                    tokenOut: address(router.WETH9()),
                    fee: 3000,
                    recipient: address(this),
                    deadline: block.timestamp + 600,
                    amountOut: amounts[1],
                    amountInMaximum: type(uint256).max,
                    sqrtPriceLimitX96: 0
                })
            ).sqrtPriceX96);
            
            // Burn liquidity
            pool.burn(
                address(this),
                amounts[1],
                0
            );
            
            // Transfer ETH to the contract owner or do something else with it
            
        }
    }
}
