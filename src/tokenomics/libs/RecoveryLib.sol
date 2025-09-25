// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibPRNG} from "../../../lib/solady/src/utils/LibPRNG.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IBurnableERC20} from "../../interfaces/IBurnableERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUniswapV3Pool} from "../../integrations/uniswapv3/IUniswapV3Pool.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {IControllable} from "../../interfaces/IControllable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMetaVault} from "../../interfaces/IMetaVault.sol";
import {IWrappedMetaVault} from "../../interfaces/IWrappedMetaVault.sol";

library RecoveryLib {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.Recovery")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant _RECOVERY_STORAGE_LOCATION =
        0xa66d1b580930935bfabcf1fd52b7ed6cbbde4be7c22c150ca93844cf61663900;

    uint internal constant SWAP_PRICE_IMPACT_TOLERANCE = 20_000; // 20%

    //region -------------------------------------- Data types

    error UnauthorizedCallback();
    error NotWhitelisted();
    error NotSwapping();
    error InvalidSwapAmount();
    error InsufficientBalance();
    error SwapFailed();
    error WrongRecoveryPoolIndex();
    error NotFound();
    error AlreadyExists();
    error InvalidTokenPair();

    event AddRecoveryPools(address[] newRecoveryPools);
    event RemoveRecoveryPool(address removedRecoveryPool);
    event RecoveryTokensPurchased(
        address pool, uint amountInMax, uint amountIn, uint amountOut, uint160 finalSqrtPriceX96
    );
    event RegisterTokens(address[] tokens);
    event SetThresholds(address[] tokens, uint[] thresholds);
    event Whitelist(address operator, bool add);
    event OnSwapFailed(address asset, address token, uint amount);

    /// @custom:storage-location erc7201:stability.Recovery
    struct RecoveryStorage {
        /// @notice UniswapV3 pools with recovery tokens
        /// Assume that all recovery pools have a recovery token as token 0 and a meta-vault-token as token 1
        EnumerableSet.AddressSet recoveryPools;
        /// @notice Minimum thresholds for tokens to trigger a swap
        mapping(address token => uint threshold) tokenThresholds;
        /// @notice Whitelisted operators that can call main actions
        mapping(address operator => bool allowed) whitelistOperators;
        /// @notice All tokens with not zero amounts - possible swap sources
        EnumerableSet.AddressSet registeredTokens;
        /// @notice True if the contract is currently performing a token swap
        bool swapping;
    }

    //endregion -------------------------------------- Data types

    //region -------------------------------------- View

    /// @notice Get current price in the given Uniswap V3 pool
    function getCurrentSqrtPriceX96(address pool) internal view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
    }

    /// @notice Select a pool using pseudo-random generator seeded by {seed}.
    /// If the generated index is even then return index/2.
    /// If the generated index is odd then return index of the pool with minimum price.
    /// This approach gives 50% chance to select the pool with minimum price and 50% chance to select another pool.
    /// This is done to avoid always selecting the same pool with minimum price.
    /// @param seed Seed for pseudo-random generator
    /// @param recoveryPools List of recovery pools
    /// @return index0 Selected pool 0-based index
    function selectPool(uint seed, address[] memory recoveryPools) internal view returns (uint index0) {
        uint countPools = recoveryPools.length;
        LibPRNG.PRNG memory prng;
        LibPRNG.seed(prng, seed);
        uint index = LibPRNG.next(prng) % countPools;
        if (index % 2 == 0) {
            return index / 2;
        } else {
            return getPoolWithMinPrice(recoveryPools);
        }
    }

    /// @notice Get index of the pool with minimum price
    function getPoolWithMinPrice(address[] memory recoveryPools) internal view returns (uint index0) {
        uint len = recoveryPools.length;
        if (len != 0) {
            uint160 minPrice = getCurrentSqrtPriceX96(recoveryPools[0]);
            for (uint i = 1; i < len; ++i) {
                uint160 price = getCurrentSqrtPriceX96(recoveryPools[i]);
                if (price < minPrice) {
                    minPrice = price;
                    index0 = i;
                }
            }
        }
        return index0;
    }
    //endregion -------------------------------------- View

    //region -------------------------------------- Governance actions
    function addRecoveryPool(address[] memory recoveryPools_) internal {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        uint len = recoveryPools_.length;
        for (uint i; i < len; ++i) {
            require($.recoveryPools.add(recoveryPools_[i]), AlreadyExists());
        }
        emit AddRecoveryPools(recoveryPools_);
    }

    function removeRecoveryPool(address pool_) internal {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        require($.recoveryPools.remove(pool_), NotFound());
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

    function changeWhitelist(address operator_, bool add_) internal {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        $.whitelistOperators[operator_] = add_;

        emit Whitelist(operator_, add_);
    }

    //endregion -------------------------------------- Governance actions

    //region -------------------------------------- Actions

    /// @notice Register income. Select a pool with minimum price and detect its token 1.
    /// Swap all {tokens} to the token1. Buy recovery tokens using token 1.
    function registerAssets(address[] memory tokens_) internal {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();

        emit RegisterTokens(tokens_);
        uint len = tokens_.length;
        for (uint i; i < len; ++i) {
            $.registeredTokens.add(tokens_[i]);
        }
    }

    /// @notice Use available tokens to buy and burn recovery tokens from the registered pools.
    /// Start swapping from the pool with the given index.
    /// If index is zero then the initial pool will be selected automatically.
    /// Swapping is done in a circular manner starting from selected pool - after the last pool the first one is used.
    /// @param indexFirstRecoveryPool1 1-based index of the recovery pool from which swapping should be started.
    /// If zero then the initial pool will be selected automatically.
    /// Max swap amount for each pool is limited by price - result prices cannot exceed 1.
    /// If price reaches 1 the remain amount should be used for swapping in other pools.
    function swapAssetsToRecoveryTokens(uint indexFirstRecoveryPool1, ISwapper swapper_) internal {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();

        address[] memory _recoveryPools = $.recoveryPools.values();

        // assume here that recovery tokens are always set as token 0, meta-vault-tokens as token 1
        // we need all tokens to prevent swapping one meta-vault-token to another
        // for main token we disable last-block-defense mechanism to allow multiple swaps in one block
        // but for other tokens we keep last-block-defense enabled
        // so it's not allowed to swap one meta-vault-token to another
        address[] memory _allMetaVaultTokens = _getAllMetaVaultTokens(_recoveryPools);

        if (_recoveryPools.length != 0) {
            require(indexFirstRecoveryPool1 <= _recoveryPools.length, WrongRecoveryPoolIndex());

            // ----------------------------------- Select target pool
            uint indexTargetPool =
                indexFirstRecoveryPool1 == 0 ? selectPool(block.timestamp, _recoveryPools) : indexFirstRecoveryPool1 - 1;
            EnumerableSet.AddressSet storage _tokens = $.registeredTokens;

            // assume here that recovery tokens are always set as token 0, meta-vault-tokens as token 1
            address metaVaultToken = IUniswapV3Pool(_recoveryPools[indexTargetPool]).token1();
            IMetaVault(IWrappedMetaVault(metaVaultToken).metaVault()).setLastBlockDefenseDisabledTx(
                uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1)
            );

            // ----------------------------------- Get amounts to swap (full balance if above threshold)
            uint lenInputAssets = _tokens.length();
            uint[] memory amountsToSwap = new uint[](lenInputAssets);
            for (uint i; i < lenInputAssets; ++i) {
                address token = _tokens.at(i);
                uint balance = IERC20(token).balanceOf(address(this));
                if (balance > $.tokenThresholds[token]) {
                    amountsToSwap[i] = balance;
                }
            }

            // ----------------------------------- Swap all amounts to the asset
            for (uint i; i < lenInputAssets; ++i) {
                address token = _tokens.at(i);
                if (amountsToSwap[i] != 0 && !_contains(_allMetaVaultTokens, token)) {
                    _approveIfNeeds(token, amountsToSwap[i], address(swapper_));

                    // hide swap errors in same way as in RevenueRouter
                    try swapper_.swap(token, metaVaultToken, amountsToSwap[i], SWAP_PRICE_IMPACT_TOLERANCE) {}
                    catch {
                        emit OnSwapFailed(token, metaVaultToken, amountsToSwap[i]);
                    }
                }
            }

            // ----------------------------------- Swap the asset to recovery tokens
            uint assetThreshold = $.tokenThresholds[metaVaultToken];
            uint amount = _swapAndBurn(_recoveryPools[indexTargetPool], metaVaultToken, assetThreshold);
            if (amount > assetThreshold) {
                // swap in a circular manner starting from the next pool
                // we skip all pools with different asset than the target pool asset
                // to avoid swapping one meta-vault-token to another

                for (uint i = indexTargetPool + 1; i < _recoveryPools.length; ++i) {
                    if (amount < assetThreshold) break;
                    if (metaVaultToken != IUniswapV3Pool(_recoveryPools[i]).token1()) continue;
                    amount = _swapAndBurn(_recoveryPools[i], metaVaultToken, assetThreshold);
                }

                for (uint i; i < indexTargetPool; ++i) {
                    if (amount < assetThreshold) break;
                    if (metaVaultToken != IUniswapV3Pool(_recoveryPools[i]).token1()) continue;
                    amount = _swapAndBurn(_recoveryPools[i], metaVaultToken, assetThreshold);
                }
            }

            IMetaVault(IWrappedMetaVault(metaVaultToken).metaVault()).setLastBlockDefenseDisabledTx(
                uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0)
            );
        }
    }

    function uniswapV3SwapCallback(int amount0Delta, int amount1Delta, bytes calldata /* data */ ) internal {
        RecoveryStorage storage $ = getRecoveryTokenStorage();
        address pool = msg.sender;

        require($.recoveryPools.contains(pool), UnauthorizedCallback());
        require($.swapping, NotSwapping());

        if (amount0Delta > 0) {
            IERC20(IUniswapV3Pool(pool).token0()).safeTransfer(address(pool), uint(amount0Delta));
        }
        if (amount1Delta > 0) {
            IERC20(IUniswapV3Pool(pool).token1()).safeTransfer(address(pool), uint(amount1Delta));
        }
    }
    //endregion -------------------------------------- Actions

    //region -------------------------------------- Internal logic
    /// @notice Swap the given asset to recovery token of the given pool and burn it.
    /// @param targetPool Uniswap V3 pool address
    /// @param asset Address of meta-vault token
    /// @return amount Remaining amount of asset after swap and burn
    function _swapAndBurn(address targetPool, address asset, uint assetThreshold) internal returns (uint amount) {
        // assume here that recovery tokens are always set as token 0
        address recoveryToken = IUniswapV3Pool(targetPool).token0();

        // we cannot use swapper here because we need to limit result price by SQRT_PRICE_LIMIT_X96
        // IERC20(asset).approve(address(swapper_), amount);
        // swapper_.swap(asset, recoveryToken, amount, 20_000);
        uint amountToSwap = IERC20(asset).balanceOf(address(this));
        if (amountToSwap > assetThreshold) {
            _swapToRecoveryToken(targetPool, asset, IERC20(asset).balanceOf(address(this)));
            uint balance = IERC20(recoveryToken).balanceOf(address(this));
            if (balance != 0) {
                IBurnableERC20(recoveryToken).burn(balance);
            }

            return IERC20(asset).balanceOf(address(this));
        } else {
            return 0;
        }
    }

    /// @notice Buy recovery-token of the given pool for meta-vault token.
    /// @param pool_ Uniswap V3 pool address
    /// @param tokenIn Address of meta-vault token
    /// @param amountInMax Maximum amount of tokenIn to spend.
    /// Actual amount is set by price limit - result price cannot exceed 1.
    function _swapToRecoveryToken(address pool_, address tokenIn, uint amountInMax) internal {
        RecoveryStorage storage $ = getRecoveryTokenStorage();
        require(amountInMax != 0, InvalidSwapAmount());

        uint balanceIn = IERC20(tokenIn).balanceOf(address(this));
        if (balanceIn < amountInMax) {
            revert InsufficientBalance();
        }

        uint160 currentSqrtPriceX96 = getCurrentSqrtPriceX96(pool_);

        address token0 = IUniswapV3Pool(pool_).token0();
        uint160 sqrtPriceLimitX96 = _sqrtPriceLimitX96(token0, IUniswapV3Pool(pool_).token1());

        if (currentSqrtPriceX96 < sqrtPriceLimitX96) {
            bool zeroForOne = token0 == tokenIn;

            $.swapping = true;

            try IUniswapV3Pool(pool_).swap(
                address(this), // recipient
                zeroForOne,
                int(amountInMax), // exactInput
                sqrtPriceLimitX96, // sqrtPriceLimitX96
                "" // data
            ) returns (int amount0, int amount1) {
                $.swapping = false;

                uint amountOut = zeroForOne ? uint(-amount1) : uint(-amount0);
                uint amountIn = zeroForOne ? uint(-amount0) : uint(-amount1);
                uint160 finalSqrtPrice = getCurrentSqrtPriceX96(pool_);

                emit RecoveryTokensPurchased(pool_, amountInMax, amountIn, amountOut, finalSqrtPrice);
            } catch {
                $.swapping = false;
                revert SwapFailed();
            }
        }
    }

    //endregion -------------------------------------- Internal logic

    //region -------------------------------------- Utils

    function getRecoveryTokenStorage() internal pure returns (RecoveryStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _RECOVERY_STORAGE_LOCATION
        }
    }

    /// @notice Make infinite approve of {token} to {spender} if the approved amount is less than {amount}
    /// @dev Should NOT be used for third-party pools
    function _approveIfNeeds(address token, uint amount, address spender) internal {
        // slither-disable-next-line calls-loop
        if (IERC20(token).allowance(address(this), spender) < amount) {
            IERC20(token).forceApprove(spender, type(uint).max);
        }
    }

    /// @notice Get price 1 for a pair of tokens with different decimals
    function _sqrtPriceLimitX96(address token0, address token1) internal view returns (uint160) {
        uint decimals0 = IERC20Metadata(token0).decimals();
        uint decimals1 = IERC20Metadata(token1).decimals();

        // assume here that recovery tokens are always set as token 0 and they have 6 or 18 decimals
        // assume also that all wrapped meta vault tokens used as token 1 have 18 decimals
        require(decimals0 <= decimals1 && (decimals1 - decimals0) % 2 == 0, InvalidTokenPair());
        return uint160((1 << 96) * 10 ** ((decimals1 - decimals0) / 2));
    }

    /// @notice Enumerate all pools, extract token1 and return the list of unique token1 addresses
    function _getAllMetaVaultTokens(address[] memory _recoveryPools) internal view returns (address[] memory) {
        uint countNotZero;
        address[] memory _allMetaVaultTokens = new address[](_recoveryPools.length);
        for (uint i; i < _recoveryPools.length; ++i) {
            address token1 = IUniswapV3Pool(_recoveryPools[i]).token1();
            if (!_contains(_allMetaVaultTokens, token1)) {
                _allMetaVaultTokens[i] = token1;
                countNotZero++;
            }
        }

        return _removeEmpty(_allMetaVaultTokens, countNotZero);
    }

    /// @return true if {value} is in {array}
    function _contains(address[] memory array, address value) internal pure returns (bool) {
        for (uint i; i < array.length; ++i) {
            if (array[i] == value) {
                return true;
            }
        }
        return false;
    }

    /// @notice Remove zero items from the given array
    function _removeEmpty(address[] memory items, uint countNotZero) internal pure returns (address[] memory dest) {
        uint len = items.length;
        dest = new address[](countNotZero);

        uint index = 0;
        for (uint i; i < len; ++i) {
            if (items[i] != address(0)) {
                dest[index] = items[i];
                index++;
            }
        }
    }

    //endregion -------------------------------------- Utils
}
