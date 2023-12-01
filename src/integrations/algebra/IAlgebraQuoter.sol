// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Restored from 0xa15F0D7377B2A0C0c10db057f641beD21028FC89
interface IAlgebraQuoter {
    function WNativeToken() external view returns (address);

    function algebraSwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory path
    ) external view;

    function factory() external view returns (address);

    function poolDeployer() external view returns (address);

    function quoteExactInput(bytes memory path, uint256 amountIn)
    external
    returns (uint256 amountOut, uint16[] memory fees);

    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint160 limitSqrtPrice
    ) external returns (uint256 amountOut, uint16 fee);

    function quoteExactOutput(bytes memory path, uint256 amountOut)
    external
    returns (uint256 amountIn, uint16[] memory fees);

    function quoteExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint160 limitSqrtPrice
    ) external returns (uint256 amountIn, uint16 fee);
}

