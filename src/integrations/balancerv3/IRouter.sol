// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AddLiquidityKind, RemoveLiquidityKind, SwapKind} from "./VaultTypes.sol";

/// @notice User-friendly interface to basic Vault operations: swap, add/remove liquidity, and associated queries.
interface IRouter {
    /**
     *
     *                             Pool Initialization
     *
     */

    /**
     * @notice Data for the pool initialization hook.
     * @param sender Account originating the pool initialization operation
     * @param pool Address of the liquidity pool
     * @param tokens Pool tokens, in token registration order
     * @param exactAmountsIn Exact amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to add initial liquidity
     */
    struct InitializeHookParams {
        address sender;
        address pool;
        IERC20[] tokens;
        uint[] exactAmountsIn;
        uint minBptAmountOut;
        bool wethIsEth;
        bytes userData;
    }

    /**
     * @notice Initialize a liquidity pool.
     * @param pool Address of the liquidity pool
     * @param tokens Pool tokens, in token registration order
     * @param exactAmountsIn Exact amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to add initial liquidity
     * @return bptAmountOut Actual amount of pool tokens minted in exchange for initial liquidity
     */
    function initialize(
        address pool,
        IERC20[] memory tokens,
        uint[] memory exactAmountsIn,
        uint minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint bptAmountOut);

    /**
     *
     *                                Add Liquidity
     *
     */

    /**
     * @notice Adds liquidity to a pool with proportional token amounts, receiving an exact amount of pool tokens.
     * @param pool Address of the liquidity pool
     * @param maxAmountsIn Maximum amounts of tokens to be added, sorted in token registration order
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to add liquidity
     * @return amountsIn Actual amounts of tokens added, sorted in token registration order
     */
    function addLiquidityProportional(
        address pool,
        uint[] memory maxAmountsIn,
        uint exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint[] memory amountsIn);

    /**
     * @notice Adds liquidity to a pool with arbitrary token amounts.
     * @param pool Address of the liquidity pool
     * @param exactAmountsIn Exact amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to add liquidity
     * @return bptAmountOut Actual amount of pool tokens received
     */
    function addLiquidityUnbalanced(
        address pool,
        uint[] memory exactAmountsIn,
        uint minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint bptAmountOut);

    /**
     * @notice Adds liquidity to a pool in a single token, receiving an exact amount of pool tokens.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token used to add liquidity
     * @param maxAmountIn Maximum amount of tokens to be added
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to add liquidity
     * @return amountIn Actual amount of tokens added
     */
    function addLiquiditySingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        uint maxAmountIn,
        uint exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint amountIn);

    /**
     * @notice Adds liquidity to a pool by donating the amounts in (no BPT out).
     * @dev To support donation, the pool config `enableDonation` flag must be set to true.
     * @param pool Address of the liquidity pool
     * @param amountsIn Amounts of tokens to be donated, sorted in token registration order
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to donate liquidity
     */
    function donate(address pool, uint[] memory amountsIn, bool wethIsEth, bytes memory userData) external payable;

    /**
     * @notice Adds liquidity to a pool with a custom request.
     * @dev The given maximum and minimum amounts given may be interpreted as exact depending on the pool type.
     * In any case the caller can expect them to be hard boundaries for the request.
     *
     * @param pool Address of the liquidity pool
     * @param maxAmountsIn Maximum amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to add liquidity
     * @return amountsIn Actual amounts of tokens added, sorted in token registration order
     * @return bptAmountOut Actual amount of pool tokens received
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function addLiquidityCustom(
        address pool,
        uint[] memory maxAmountsIn,
        uint minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint[] memory amountsIn, uint bptAmountOut, bytes memory returnData);

    /**
     *
     *                              Remove Liquidity
     *
     */

    /**
     * @notice Removes liquidity with proportional token amounts from a pool, burning an exact pool token amount.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to remove liquidity
     * @return amountsOut Actual amounts of tokens received, sorted in token registration order
     */
    function removeLiquidityProportional(
        address pool,
        uint exactBptAmountIn,
        uint[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint[] memory amountsOut);

    /**
     * @notice Removes liquidity from a pool via a single token, burning an exact pool token amount.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param tokenOut Token used to remove liquidity
     * @param minAmountOut Minimum amount of tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to remove liquidity
     * @return amountOut Actual amount of tokens received
     */
    function removeLiquiditySingleTokenExactIn(
        address pool,
        uint exactBptAmountIn,
        IERC20 tokenOut,
        uint minAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint amountOut);

    /**
     * @notice Removes liquidity from a pool via a single token, specifying the exact amount of tokens to receive.
     * @param pool Address of the liquidity pool
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param tokenOut Token used to remove liquidity
     * @param exactAmountOut Exact amount of tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to remove liquidity
     * @return bptAmountIn Actual amount of pool tokens burned
     */
    function removeLiquiditySingleTokenExactOut(
        address pool,
        uint maxBptAmountIn,
        IERC20 tokenOut,
        uint exactAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint bptAmountIn);

    /**
     * @notice Removes liquidity from a pool with a custom request.
     * @dev The given maximum and minimum amounts given may be interpreted as exact depending on the pool type.
     * In any case the caller can expect them to be hard boundaries for the request.
     *
     * @param pool Address of the liquidity pool
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to remove liquidity
     * @return bptAmountIn Actual amount of pool tokens burned
     * @return amountsOut Actual amounts of tokens received, sorted in token registration order
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function removeLiquidityCustom(
        address pool,
        uint maxBptAmountIn,
        uint[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint bptAmountIn, uint[] memory amountsOut, bytes memory returnData);

    /**
     * @notice Removes liquidity proportionally, burning an exact pool token amount. Only available in Recovery Mode.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
     * @return amountsOut Actual amounts of tokens received, sorted in token registration order
     */
    function removeLiquidityRecovery(
        address pool,
        uint exactBptAmountIn,
        uint[] memory minAmountsOut
    ) external payable returns (uint[] memory amountsOut);

    /**
     *
     *                                    Swaps
     *
     */

    /**
     * @notice Data for the swap hook.
     * @param sender Account initiating the swap operation
     * @param kind Type of swap (exact in or exact out)
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param amountGiven Amount given based on kind of the swap (e.g., tokenIn for exact in)
     * @param limit Maximum or minimum amount based on the kind of swap (e.g., maxAmountIn for exact out)
     * @param deadline Deadline for the swap, after which it will revert
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the swap request
     */
    struct SwapSingleTokenHookParams {
        address sender;
        SwapKind kind;
        address pool;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint amountGiven;
        uint limit;
        uint deadline;
        bool wethIsEth;
        bytes userData;
    }

    /**
     * @notice Executes a swap operation specifying an exact input token amount.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountIn Exact amounts of input tokens to send
     * @param minAmountOut Minimum amount of tokens to be received
     * @param deadline Deadline for the swap, after which it will revert
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the swap request
     * @return amountOut Calculated amount of output tokens to be received in exchange for the given input tokens
     */
    function swapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint exactAmountIn,
        uint minAmountOut,
        uint deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint amountOut);

    /**
     * @notice Executes a swap operation specifying an exact output token amount.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountOut Exact amounts of input tokens to receive
     * @param maxAmountIn Maximum amount of tokens to be sent
     * @param deadline Deadline for the swap, after which it will revert
     * @param userData Additional (optional) data sent with the swap request
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @return amountIn Calculated amount of input tokens to be sent in exchange for the requested output tokens
     */
    function swapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint exactAmountOut,
        uint maxAmountIn,
        uint deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint amountIn);

    /**
     *
     *                                   Queries
     *
     */

    /**
     * @notice Queries an `addLiquidityProportional` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountsIn Expected amounts of tokens to add, sorted in token registration order
     */
    function queryAddLiquidityProportional(
        address pool,
        uint exactBptAmountOut,
        address sender,
        bytes memory userData
    ) external returns (uint[] memory amountsIn);

    /**
     * @notice Queries an `addLiquidityUnbalanced` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactAmountsIn Exact amounts of tokens to be added, sorted in token registration order
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return bptAmountOut Expected amount of pool tokens to receive
     */
    function queryAddLiquidityUnbalanced(
        address pool,
        uint[] memory exactAmountsIn,
        address sender,
        bytes memory userData
    ) external returns (uint bptAmountOut);

    /**
     * @notice Queries an `addLiquiditySingleTokenExactOut` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token used to add liquidity
     * @param exactBptAmountOut Expected exact amount of pool tokens to receive
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountIn Expected amount of tokens to add
     */
    function queryAddLiquiditySingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        uint exactBptAmountOut,
        address sender,
        bytes memory userData
    ) external returns (uint amountIn);

    /**
     * @notice Queries an `addLiquidityCustom` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param maxAmountsIn Maximum amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Expected minimum amount of pool tokens to receive
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountsIn Expected amounts of tokens to add, sorted in token registration order
     * @return bptAmountOut Expected amount of pool tokens to receive
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function queryAddLiquidityCustom(
        address pool,
        uint[] memory maxAmountsIn,
        uint minBptAmountOut,
        address sender,
        bytes memory userData
    ) external returns (uint[] memory amountsIn, uint bptAmountOut, bytes memory returnData);

    /**
     * @notice Queries a `removeLiquidityProportional` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountsOut Expected amounts of tokens to receive, sorted in token registration order
     */
    function queryRemoveLiquidityProportional(
        address pool,
        uint exactBptAmountIn,
        address sender,
        bytes memory userData
    ) external returns (uint[] memory amountsOut);

    /**
     * @notice Queries a `removeLiquiditySingleTokenExactIn` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @param tokenOut Token used to remove liquidity
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountOut Expected amount of tokens to receive
     */
    function queryRemoveLiquiditySingleTokenExactIn(
        address pool,
        uint exactBptAmountIn,
        IERC20 tokenOut,
        address sender,
        bytes memory userData
    ) external returns (uint amountOut);

    /**
     * @notice Queries a `removeLiquiditySingleTokenExactOut` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenOut Token used to remove liquidity
     * @param exactAmountOut Expected exact amount of tokens to receive
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return bptAmountIn Expected amount of pool tokens to burn
     */
    function queryRemoveLiquiditySingleTokenExactOut(
        address pool,
        IERC20 tokenOut,
        uint exactAmountOut,
        address sender,
        bytes memory userData
    ) external returns (uint bptAmountIn);

    /**
     * @notice Queries a `removeLiquidityCustom` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param minAmountsOut Expected minimum amounts of tokens to receive, sorted in token registration order
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return bptAmountIn Expected amount of pool tokens to burn
     * @return amountsOut Expected amounts of tokens to receive, sorted in token registration order
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function queryRemoveLiquidityCustom(
        address pool,
        uint maxBptAmountIn,
        uint[] memory minAmountsOut,
        address sender,
        bytes memory userData
    ) external returns (uint bptAmountIn, uint[] memory amountsOut, bytes memory returnData);

    /**
     * @notice Queries a `removeLiquidityRecovery` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @return amountsOut Expected amounts of tokens to receive, sorted in token registration order
     */
    function queryRemoveLiquidityRecovery(
        address pool,
        uint exactBptAmountIn
    ) external returns (uint[] memory amountsOut);

    /**
     * @notice Queries a swap operation specifying an exact input token amount without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountIn Exact amounts of input tokens to send
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountOut Calculated amount of output tokens to be received in exchange for the given input tokens
     */
    function querySwapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint exactAmountIn,
        address sender,
        bytes calldata userData
    ) external returns (uint amountOut);

    /**
     * @notice Queries a swap operation specifying an exact output token amount without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountOut Exact amounts of input tokens to receive
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountIn Calculated amount of input tokens to be sent in exchange for the requested output tokens
     */
    function querySwapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint exactAmountOut,
        address sender,
        bytes calldata userData
    ) external returns (uint amountIn);
}
