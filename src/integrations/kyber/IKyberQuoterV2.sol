// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

///@notice Restored from 0x4d47fd5a29904Dae0Ef51b1c450C9750F15D7856
interface IKyberQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint amountIn;
        uint24 feeUnits;
        uint160 limitSqrtP;
    }

    struct QuoteOutput {
        uint usedAmount;
        uint returnedAmount;
        uint160 afterSqrtP;
        uint32 initializedTicksCrossed;
        uint gasEstimate;
    }

    struct QuoteExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint amount;
        uint24 feeUnits;
        uint160 limitSqrtP;
    }

    function factory() external view returns (address);

    function quoteExactInput(
        bytes memory path,
        uint amountIn
    )
        external
        returns (
            uint amountOut,
            uint160[] memory afterSqrtPList,
            uint32[] memory initializedTicksCrossedList,
            uint gasEstimate
        );

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (QuoteOutput memory output);

    function quoteExactOutput(
        bytes memory path,
        uint amountOut
    )
        external
        returns (
            uint amountIn,
            uint160[] memory afterSqrtPList,
            uint32[] memory initializedTicksCrossedList,
            uint gasEstimate
        );

    function quoteExactOutputSingle(QuoteExactOutputSingleParams memory params)
        external
        returns (QuoteOutput memory output);

    function swapCallback(int amount0Delta, int amount1Delta, bytes memory path) external view;
}
