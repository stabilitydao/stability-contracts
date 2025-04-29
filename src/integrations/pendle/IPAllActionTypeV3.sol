// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import "./IPSwapAggregator.sol";
import "./IPLimitRouter.sol";
import {IPYieldToken} from "./IPYieldToken.sol";

/*
 * NOTICE:
 * For detailed information on TokenInput, TokenOutput, ApproxParams, and LimitOrderData,
 * refer to https://docs.pendle.finance/Developers/Contracts/PendleRouter
 *
 * It's recommended to use Pendle's Hosted SDK to generate these parameters for:
 * 1. Optimal liquidity and gas efficiency
 * 2. Access to deeper liquidity via limit orders
 * 3. Zapping in/out using any ERC20 token
 *
 * Else, to generate these parameters fully onchain, use the following functions:
 * - For TokenInput: Use createTokenInputSimple
 * - For TokenOutput: Use createTokenOutputSimple
 * - For ApproxParams: Use createDefaultApproxParams
 * - For LimitOrderData: Use createEmptyLimitOrderData
 *
 * These generated parameters can be directly passed into the respective function calls.
 *
 * Examples:
 *
 * addLiquiditySingleToken(
 *     msg.sender,
 *     MARKET_ADDRESS,
 *     minLpOut,
 *     createDefaultApproxParams(),
 *     createTokenInputSimple(USDC_ADDRESS, 1000e6),
 *     createEmptyLimitOrderData()
 * )
 *
 * swapExactTokenForPt(
 *     msg.sender,
 *     MARKET_ADDRESS,
 *     minPtOut,
 *     createDefaultApproxParams(),
 *     createTokenInputSimple(USDC_ADDRESS, 1000e6),
 *     createEmptyLimitOrderData()
 * )
 */

/// @dev Creates a TokenInput struct without using any swap aggregator
/// @param tokenIn must be one of the SY's tokens in (obtain via `IStandardizedYield#getTokensIn`)
/// @param netTokenIn amount of token in
function createTokenInputSimple(address tokenIn, uint netTokenIn) pure returns (TokenInput memory) {
    return TokenInput({
        tokenIn: tokenIn,
        netTokenIn: netTokenIn,
        tokenMintSy: tokenIn,
        pendleSwap: address(0),
        swapData: createSwapTypeNoAggregator()
    });
}

/// @dev Creates a TokenOutput struct without using any swap aggregator
/// @param tokenOut must be one of the SY's tokens out (obtain via `IStandardizedYield#getTokensOut`)
/// @param minTokenOut minimum amount of token out
function createTokenOutputSimple(address tokenOut, uint minTokenOut) pure returns (TokenOutput memory) {
    return TokenOutput({
        tokenOut: tokenOut,
        minTokenOut: minTokenOut,
        tokenRedeemSy: tokenOut,
        pendleSwap: address(0),
        swapData: createSwapTypeNoAggregator()
    });
}

function createEmptyLimitOrderData() pure returns (LimitOrderData memory) {}

/// @dev Creates default ApproxParams for on-chain approximation
function createDefaultApproxParams() pure returns (ApproxParams memory) {
    return ApproxParams({guessMin: 0, guessMax: type(uint).max, guessOffchain: 0, maxIteration: 256, eps: 1e14});
}

function createSwapTypeNoAggregator() pure returns (SwapData memory) {}

struct TokenInput {
    address tokenIn;
    uint netTokenIn;
    address tokenMintSy;
    address pendleSwap;
    SwapData swapData;
}

struct TokenOutput {
    address tokenOut;
    uint minTokenOut;
    address tokenRedeemSy;
    address pendleSwap;
    SwapData swapData;
}

struct LimitOrderData {
    address limitRouter;
    uint epsSkipMarket;
    FillOrderParams[] normalFills;
    FillOrderParams[] flashFills;
    bytes optData;
}

struct ApproxParams {
    uint guessMin;
    uint guessMax;
    uint guessOffchain;
    uint maxIteration;
    uint eps;
}

struct ExitPreExpReturnParams {
    uint netPtFromRemove;
    uint netSyFromRemove;
    uint netPyRedeem;
    uint netSyFromRedeem;
    uint netPtSwap;
    uint netYtSwap;
    uint netSyFromSwap;
    uint netSyFee;
    uint totalSyOut;
}

struct ExitPostExpReturnParams {
    uint netPtFromRemove;
    uint netSyFromRemove;
    uint netPtRedeem;
    uint netSyFromRedeem;
    uint totalSyOut;
}

struct RedeemYtIncomeToTokenStruct {
    IPYieldToken yt;
    bool doRedeemInterest;
    bool doRedeemRewards;
    address tokenRedeemSy;
    uint minTokenRedeemOut;
}
