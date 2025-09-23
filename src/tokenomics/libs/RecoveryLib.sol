// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../../lib/solady/src/utils/LibPRNG.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IBurnableERC20} from "../../interfaces/IBurnableERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRecoveryToken} from "../../interfaces/IRecoveryToken.sol";
import {IUniswapV3Pool} from "../../integrations/uniswapv3/IUniswapV3Pool.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {IControllable} from "../../interfaces/IControllable.sol";

library RecoveryLib {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint160 public constant SQRT_PRICE_LIMIT_X96 = uint160(1 << 96); // 79228162514264337593543950336; // sqrt(1) * 2^96

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.Recovery")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant _RECOVERY_STORAGE_LOCATION = 0xa66d1b580930935bfabcf1fd52b7ed6cbbde4be7c22c150ca93844cf61663900;

    //region -------------------------------------- Data types

    error UnauthorizedCallback();
    error NotSwapping();
    error InvalidSwapAmount();
    error InsufficientBalance();
    error SwapFailed();

    event AddRecoveryPools(address[] newRecoveryPools);
    event RemoveRecoveryPool(address removedRecoveryPool);
    event RecoveryTokensPurchased(uint256 amountIn, uint256 amountOut, uint160 finalSqrtPriceX96);
    event ReceiveAmounts(address[] tokens, uint256[] amounts);
    event SetThresholds(address[] tokens, uint256[] thresholds);

    /// @custom:storage-location erc7201:stability.Recovery
    struct RecoveryStorage {
        /// @notice UniswapV3 pools with recovery tokens
        /// Assume that all recovery pools have a recovery token as token 0 and a meta-vault-token as token 1
        EnumerableSet.AddressSet recoveryPools;

        /// @notice Minimum thresholds for tokens to trigger a swap
        mapping (address token => uint threshold) tokenThresholds;

        /// @notice True if the contract is currently performing a token swap
        bool swapping;
    }

    //endregion -------------------------------------- Data types

    //region -------------------------------------- View

    /// @notice Get current price in the given Uniswap V3 pool
    function getCurrentSqrtPriceX96(address pool) internal view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
    }

    function selectPool(RecoveryLib.RecoveryStorage storage $, uint seed) internal view returns (address) {
        uint countPools = $.recoveryPools.length();
        LibPRNG.PRNG memory prng;
        LibPRNG.seed(prng, seed);
        uint index = LibPRNG.next(prng) % countPools;
        if (index % 2 == 0) {
            return $.recoveryPools.at(index / 2);
        } else {
            return getPoolWithMinPrice($);
        }
    }

    function getPoolWithMinPrice(RecoveryStorage storage $) internal view returns (address targetPool) {
        uint len = $.recoveryPools.length();
        if (len != 0) {
            targetPool = $.recoveryPools.at(0);
            uint160 minPrice = getCurrentSqrtPriceX96(targetPool);
            for (uint i = 1; i < len; ++i) {
                address pool = $.recoveryPools.at(i);
                uint160 price = getCurrentSqrtPriceX96(pool);
                if (price < minPrice) {
                    minPrice = price;
                    targetPool = pool;
                }
            }
        }
        return targetPool;
    }
    //endregion -------------------------------------- View

    //region -------------------------------------- Restricted actions
    function addRecoveryPool(address[] memory recoveryPools_) internal {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        uint len = recoveryPools_.length;
        for (uint i; i < len; ++i) {
            $.recoveryPools.add(recoveryPools_[i]);
        }
        emit AddRecoveryPools(recoveryPools_);
    }

    function removeRecoveryPool(address pool_) internal {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        $.recoveryPools.remove(pool_);
        emit RemoveRecoveryPool(pool_);
    }

    function setThresholds(address[] memory tokens, uint[] memory thresholds) internal {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        uint len = tokens.length;
        for (uint i; i < len; ++i) {
            $.tokenThresholds[tokens[i]] = thresholds[i];
        }
        emit SetThresholds(tokens, thresholds);
    }

    //endregion -------------------------------------- Restricted actions

    //region -------------------------------------- Actions

    /// @notice Register income. Select a pool with minimum price and detect its token 1.
    /// Swap all {tokens} to the token1. Buy recovery tokens using token 1.
    function registerTransferredAmounts(
        address[] memory tokens_,
        uint[] memory amounts_,
        ISwapper swapper
    ) internal {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();

        emit ReceiveAmounts(tokens_, amounts_);

        // ----------------------------------- Select pool
        address targetPool = selectPool($, block.timestamp);

        // assume here that recovery tokens are always token 0
        address asset = IUniswapV3Pool(targetPool).token1();
        address recoveryToken = IUniswapV3Pool(targetPool).token0();

        // ----------------------------------- Get amounts to swap (full balance if above threshold)
        uint[] memory amountsToSwap = new uint[](tokens_.length);
        uint len = tokens_.length;
        for (uint i; i < len; ++i) {
            uint balance = IERC20(tokens_[i]).balanceOf(address(this));
            if (balance > $.tokenThresholds[tokens_[i]]) {
                amountsToSwap[i] = balance;
            }
        }

        // ----------------------------------- Swap all amounts to the asset
        for (uint i; i < len; ++i) {
            if (amountsToSwap[i] != 0 && tokens_[i] != asset) {
                try swapper.swap(asset, tokens_[i], amountsToSwap[i], 20_000) {} catch {}
            }
        }

        // ----------------------------------- Swap the asset to recovery token
        uint amount = IERC20(asset).balanceOf(address(this));
        if (amount != 0) {
            swapToRecoveryToken(targetPool, asset, amount);
            uint balance = IERC20(recoveryToken).balanceOf(address(this));
            if (balance != 0) {
                IBurnableERC20(recoveryToken).burn(amount);
            }
        }

        // todo check remaining balance and use it for the next swap
    }

    //endregion -------------------------------------- Actions

    //region -------------------------------------- Uniswap V3 logic

    /// @notice Buy recovery token for one of meta-vault tokens
    /// @param pool_ Uniswap V3 pool address
    /// @param tokenIn Address of meta-vault token
    /// @param amountInMax Maximum amount of tokenIn to spend
    function swapToRecoveryToken(
        address pool_,
        address tokenIn,
        uint256 amountInMax
    ) internal {
        RecoveryStorage storage $ = getRecoveryTokenStorage();
        require(amountInMax != 0, InvalidSwapAmount());

        uint256 balanceIn = IERC20(tokenIn).balanceOf(address(this));
        if (balanceIn < amountInMax) {
            revert InsufficientBalance();
        }

        uint160 currentSqrtPriceX96 = getCurrentSqrtPriceX96(pool_);
        if (currentSqrtPriceX96 <= SQRT_PRICE_LIMIT_X96) {
            bool zeroForOne = IUniswapV3Pool(pool_).token0() == tokenIn;

            $.swapping = true;

            try IUniswapV3Pool(pool_).swap(
                address(this), // recipient
                zeroForOne,
                int256(amountInMax), // exactInput
                SQRT_PRICE_LIMIT_X96, // sqrtPriceLimitX96
                "" // data
            ) returns (int256 amount0, int256 amount1) {
                $.swapping = false;

                uint256 amountOut = zeroForOne ? uint256(-amount1) : uint256(-amount0);
                uint160 finalSqrtPrice = getCurrentSqrtPriceX96(pool_);

                emit RecoveryTokensPurchased(amountInMax, amountOut, finalSqrtPrice);
            } catch {
                $.swapping = false;
                revert SwapFailed();
            }
        }
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata /* data */
    ) internal {
        RecoveryStorage storage $ = getRecoveryTokenStorage();
        address pool = msg.sender;

        require($.recoveryPools.contains(pool), UnauthorizedCallback());
        require($.swapping, NotSwapping());

        if (amount0Delta != 0) {
            IERC20(IUniswapV3Pool(pool).token0()).transfer(address(pool), uint256(amount0Delta));
        }
        if (amount1Delta != 0) {
            IERC20(IUniswapV3Pool(pool).token1()).transfer(address(pool), uint256(amount1Delta));
        }
    }

    //endregion -------------------------------------- Uniswap V3 logic

    //region -------------------------------------- Utils

    function getRecoveryTokenStorage() internal pure returns (RecoveryStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _RECOVERY_STORAGE_LOCATION
        }
    }

    //endregion -------------------------------------- Utils
}