// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

///@notice Restored from 0x4d47fd5a29904Dae0Ef51b1c450C9750F15D7856
interface IKyberQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 feeUnits;
        uint160 limitSqrtP;
    }

    struct QuoteOutput {
        uint256 usedAmount;
        uint256 returnedAmount;
        uint160 afterSqrtP;
        uint32 initializedTicksCrossed;
        uint256 gasEstimate;
    }

    struct QuoteExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amount;
        uint24 feeUnits;
        uint160 limitSqrtP;
    }


    function factory() external view returns (address);

    function quoteExactInput(bytes memory path, uint256 amountIn)
    external
    returns (
        uint256 amountOut,
        uint160[] memory afterSqrtPList,
        uint32[] memory initializedTicksCrossedList,
        uint256 gasEstimate
    );

    function quoteExactInputSingle(
        QuoteExactInputSingleParams memory params
    ) external returns (QuoteOutput memory output);

    function quoteExactOutput(bytes memory path, uint256 amountOut)
    external
    returns (
        uint256 amountIn,
        uint160[] memory afterSqrtPList,
        uint32[] memory initializedTicksCrossedList,
        uint256 gasEstimate
    );

    function quoteExactOutputSingle(
        QuoteExactOutputSingleParams memory params
    ) external returns (QuoteOutput memory output);

    function swapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory path
    ) external view;
}
