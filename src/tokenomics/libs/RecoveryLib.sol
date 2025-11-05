// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IBurnableERC20} from "../../interfaces/IBurnableERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMetaVault} from "../../interfaces/IMetaVault.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {IPriceReader} from "../../interfaces/IPriceReader.sol";
import {IUniswapV3Pool} from "../../integrations/uniswapv3/IUniswapV3Pool.sol";
import {IWrappedMetaVault} from "../../interfaces/IWrappedMetaVault.sol";
import {LibPRNG} from "../../../lib/solady/src/utils/LibPRNG.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library RecoveryLib {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.Recovery")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant _RECOVERY_STORAGE_LOCATION =
        0xa66d1b580930935bfabcf1fd52b7ed6cbbde4be7c22c150ca93844cf61663900;

    /// @notice Price impact tolerance for swapping assets to meta-vault tokens,
    uint internal constant SWAP_PRICE_IMPACT_TOLERANCE_ASSETS = 20_000;

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
    /// @notice Deprecated, replaced by SwapAssets2
    event SwapAssets(
        address[] tokens, address asset, uint balanceBefore, uint balanceAfter, address selectedRecoveryPool
    );
    event SwapAssets2(
        address token, address asset, uint balanceBefore, uint balanceAfter, address selectedRecoveryPool
    );
    event FillRecoveryPools(address metaVaultToken_, uint balanceBefore, uint balanceAfter, uint countSwaps);
    event SetReceiver(address recoveryToken, address receiver);

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
        /// @notice Allow to forward given bought recoveryToken to receiver instead of burning them
        mapping(address recoveryToken => address receiver) receivers;
    }

    //endregion -------------------------------------- Data types

    //region -------------------------------------- View

    /// @notice Get current price in the given Uniswap V3 pool
    function getCurrentSqrtPriceX96(address pool) internal view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
    }

    /// @notice Select a pool using pseudo-random generator seeded by {seed}.
    /// If the generated index is even then return index of the first pool with not unit price starting from (index / 2)
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
        uint index = LibPRNG.next(prng) % (2 * countPools);
        if (index % 2 == 0) {
            return getPoolWithNonUnitPrice(recoveryPools, index / 2);
        } else {
            return getPoolWithMinPrice(recoveryPools, prng);
        }
    }

    /// @notice Get index of the pool with non-unit price starting from the given index
    function getPoolWithNonUnitPrice(
        address[] memory recoveryPools,
        uint startFromIndex0
    ) internal view returns (uint index0) {
        uint len = recoveryPools.length;
        for (uint i; i < len; ++i) {
            index0 = (startFromIndex0 + i) % len;
            if (getNormalizedSqrtPrice(recoveryPools[index0]) != 1e18) {
                return index0;
            }
        }

        return startFromIndex0;
    }

    /// @notice Get index of the pool with minimum price
    function getPoolWithMinPrice(
        address[] memory recoveryPools,
        LibPRNG.PRNG memory prng
    ) internal view returns (uint index0) {
        uint len = recoveryPools.length;
        if (len != 0) {
            // get normalized prices for all pools and find minimum price
            // there is a chance to have several pools with same minimum price (i.e. 1)
            uint[] memory normalizedPrices = new uint[](len);
            uint minPrice = getNormalizedSqrtPrice(recoveryPools[0]);
            for (uint i; i < len; ++i) {
                normalizedPrices[i] = getNormalizedSqrtPrice(recoveryPools[i]);
                if (normalizedPrices[i] < minPrice) {
                    minPrice = normalizedPrices[i];
                    index0 = i;
                }
            }

            // select random pool - try to get it randomly from all pools with same min price
            for (uint i; i < len * 5; ++i) {
                index0 = LibPRNG.next(prng) % len;
                if (normalizedPrices[index0] == minPrice) break;
            }
        }

        return index0;
    }

    /// @notice Get normalized sqrt price (scaled to 1e18) in the given Uniswap V3 pool
    /// Result price is suitable to compare prices in pools with different token decimals
    function getNormalizedSqrtPrice(address pool) internal view returns (uint) {
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        address token0 = IUniswapV3Pool(pool).token0();
        address token1 = IUniswapV3Pool(pool).token1();

        uint8 decimals0 = IERC20Metadata(token0).decimals();
        uint8 decimals1 = IERC20Metadata(token1).decimals();

        uint sqrtPrice = uint(sqrtPriceX96) * 1e18 / (1 << 96);

        return decimals1 > decimals0
            ? sqrtPrice / (10 ** ((decimals1 - decimals0) / 2))
            : sqrtPrice * (10 ** ((decimals0 - decimals1) / 2));
    }

    /// @notice Return list of registered tokens with amounts exceeding thresholds
    /// Meta vault tokens are excluded from the list
    function getListTokensToSwap(RecoveryStorage storage $) external view returns (address[] memory tokens) {
        address[] memory metaVaultTokens = _getAllMetaVaultTokens($.recoveryPools.values());

        uint len = $.registeredTokens.length();
        address[] memory tempTokens = new address[](len);
        uint countNotZero;
        for (uint i; i < len; ++i) {
            address token = $.registeredTokens.at(i);
            uint balance = IERC20(token).balanceOf(address(this));
            if (balance > $.tokenThresholds[token] && _findItemInArray(metaVaultTokens, token) == type(uint).max) {
                tempTokens[countNotZero] = token;
                countNotZero++;
            }
        }

        return _removeEmpty(tempTokens, countNotZero);
    }

    function getListRegisteredTokens(RecoveryStorage storage $) external view returns (address[] memory tokens) {
        return $.registeredTokens.values();
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

    function setReceiver(address recoveryToken_, address receiver_) internal {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        $.receivers[recoveryToken_] = receiver_;

        emit SetReceiver(recoveryToken_, receiver_);
    }

    /// @notice Swap tokens explicitly through. It allows to swap meta-vault-tokens as well.
    /// @param tokenIn Address of the token to be swapped
    /// @param tokenOut Address of the token to receive on balance of this contract
    /// @param amountIn Amount of {tokenIn} to be swapped
    /// @param priceImpactTolerance Maximum tolerated price impact, 20_000 = 20%
    function swapExplicitly(
        ISwapper swapper_,
        IPriceReader priceReader_,
        address tokenIn,
        address tokenOut,
        uint amountIn,
        uint priceImpactTolerance
    ) internal {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();

        require(amountIn <= IERC20(tokenIn).balanceOf(address(this)), InsufficientBalance());

        address[2] memory tokens = [tokenIn, tokenOut];
        bool[2] memory isMetaVault = [false, false];

        // ------------------------- check if any of the tokens is meta-vault-token
        address[] memory recoveryPools = $.recoveryPools.values();
        for (uint i; i < recoveryPools.length; ++i) {
            address token1 = IUniswapV3Pool(recoveryPools[i]).token1();
            for (uint j; j < 2; ++j) {
                if (tokens[j] == token1) {
                    isMetaVault[j] = true;
                }
            }
        }

        // ------------------------- disable last-block-defence and enable price cache for meta-vault-tokens
        for (uint j; j < 2; ++j) {
            if (isMetaVault[j]) {
                IMetaVault metaVault = IMetaVault(IWrappedMetaVault(tokens[j]).metaVault());
                metaVault.setLastBlockDefenseDisabledTx(
                    uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1)
                );

                priceReader_.preCalculatePriceTx(tokens[j]);
                metaVault.cachePrices(false);
            }
        }

        // ------------------------- swap
        uint balanceBefore = IERC20(tokenOut).balanceOf(address(this));
        _approveIfNeeds(tokenIn, amountIn, address(swapper_));
        swapper_.swap(tokenIn, tokenOut, amountIn, priceImpactTolerance);

        emit SwapAssets2(tokenIn, tokenOut, balanceBefore, IERC20(tokenOut).balanceOf(address(this)), address(0));

        // ------------------------- disable last-block-defence back
        for (uint j; j < 2; ++j) {
            if (isMetaVault[j]) {
                IMetaVault metaVault = IMetaVault(IWrappedMetaVault(tokens[j]).metaVault());
                metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0));

                // Disable cache
                priceReader_.preCalculatePriceTx(address(0));
                metaVault.cachePrices(true);
            }
        }
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

    /// @notice Swap registered tokens to meta vault tokens. The meta vault token is selected from the given recovery pool.
    /// @param tokens Addresses of registered tokens to be swapped. They should be asked through {getListTokensToSwap}
    /// Number of tokens should be limited to avoid gas limit excess, so this function probably should be called several times
    /// to swap all available tokens.
    /// @param indexRecoveryPool1 1-based index of the recovery pool.
    /// The pools is used to select target meta vault token. If 0 the pool will be selected automatically.
    function swapAssets(
        ISwapper swapper_,
        IPriceReader priceReader_,
        address[] memory tokens,
        uint indexRecoveryPool1
    ) internal {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        uint len = tokens.length;

        address metaVaultToken;
        address[] memory _recoveryPools;
        (_recoveryPools, indexRecoveryPool1) = _getShuffledArray($.recoveryPools.values(), indexRecoveryPool1);
        if (_recoveryPools.length != 0) {
            uint index0 = _getRecoveryPool(_recoveryPools, indexRecoveryPool1);
            // assume here that recovery tokens are always set as token 0, meta-vault-tokens as token 1
            metaVaultToken = IUniswapV3Pool(_recoveryPools[index0]).token1();

            IMetaVault metaVault = IMetaVault(IWrappedMetaVault(metaVaultToken).metaVault());
            metaVault.setLastBlockDefenseDisabledTx(
                uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1)
            );

            // Swap to meta-vault-tokens take a lot of gas. We need to use cache
            priceReader_.preCalculatePriceTx(metaVaultToken);
            metaVault.cachePrices(false);

            uint balanceBefore = IERC20(metaVaultToken).balanceOf(address(this));

            for (uint i; i < len; ++i) {
                uint amount = IERC20(tokens[i]).balanceOf(address(this));
                if (amount > $.tokenThresholds[tokens[i]]) {
                    _approveIfNeeds(tokens[i], amount, address(swapper_));

                    // swapper_.swap(tokens[i], metaVaultToken, amount, SWAP_PRICE_IMPACT_TOLERANCE_ASSETS);

                    // hide swap errors in same way as in RevenueRouter
                    try swapper_.swap(tokens[i], metaVaultToken, amount, SWAP_PRICE_IMPACT_TOLERANCE_ASSETS) {
                        emit SwapAssets2(
                            tokens[i],
                            metaVaultToken,
                            balanceBefore,
                            IERC20(metaVaultToken).balanceOf(address(this)),
                            _recoveryPools[index0]
                        );
                    } catch {
                        emit OnSwapFailed(tokens[i], metaVaultToken, amount);
                    }
                }
            }

            // Disable cache
            priceReader_.preCalculatePriceTx(address(0));
            metaVault.cachePrices(true);

            metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0));
        }
    }

    /// @notice Swap meta vault tokens from the balance of this contract to recovery tokens in the registered pools
    /// @param indexFirstRecoveryPool1 1-based index of the recovery pool from which swapping should be started.
    /// If zero then the initial pool will be selected automatically.
    /// @param maxCountPools Maximum number of pools to be used for swapping. 0 - no limits
    function fillRecoveryPools(address metaVaultToken_, uint indexFirstRecoveryPool1, uint maxCountPools) internal {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();

        uint metaVaultTokenThreshold = $.tokenThresholds[metaVaultToken_];
        uint balanceBefore = IERC20(metaVaultToken_).balanceOf(address(this));

        address[] memory _recoveryPools;
        (_recoveryPools, indexFirstRecoveryPool1) = _getShuffledArray($.recoveryPools.values(), indexFirstRecoveryPool1);
        if (_recoveryPools.length != 0 && balanceBefore > metaVaultTokenThreshold) {
            IMetaVault(IWrappedMetaVault(metaVaultToken_).metaVault())
                .setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1));

            uint restAmount = balanceBefore;
            uint startPoolIndex0 = _getRecoveryPool(_recoveryPools, indexFirstRecoveryPool1);
            uint countSwaps;

            // swap in a circular manner starting from the selected pool
            // we skip all pools with different asset than the given meta-vault-token
            // to avoid swapping one meta-vault-token to another

            for (uint i = startPoolIndex0; i < _recoveryPools.length; ++i) {
                if (maxCountPools != 0 && countSwaps > maxCountPools) break;
                if (restAmount < metaVaultTokenThreshold) break;
                if (metaVaultToken_ != IUniswapV3Pool(_recoveryPools[i]).token1()) continue;
                restAmount = _swapAndBurn($, _recoveryPools[i], metaVaultToken_, metaVaultTokenThreshold);
                ++countSwaps;
            }

            for (uint i; i < startPoolIndex0; ++i) {
                if (maxCountPools != 0 && countSwaps > maxCountPools) break;
                if (restAmount < metaVaultTokenThreshold) break;
                if (metaVaultToken_ != IUniswapV3Pool(_recoveryPools[i]).token1()) continue;
                restAmount = _swapAndBurn($, _recoveryPools[i], metaVaultToken_, metaVaultTokenThreshold);
                ++countSwaps;
            }

            IMetaVault(IWrappedMetaVault(metaVaultToken_).metaVault())
                .setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0));

            emit FillRecoveryPools(metaVaultToken_, balanceBefore, restAmount, countSwaps);
        }
    }

    function uniswapV3SwapCallback(
        int amount0Delta,
        int amount1Delta,
        bytes calldata /* data */
    ) internal {
        amount0Delta; // hide warning

        RecoveryStorage storage $ = getRecoveryTokenStorage();
        address pool = msg.sender;

        require($.recoveryPools.contains(pool), UnauthorizedCallback());
        require($.swapping, NotSwapping());

        // we never send recovery tokens back to the pool
        //        if (amount0Delta > 0) {
        //            IERC20(IUniswapV3Pool(pool).token0()).safeTransfer(address(pool), uint(amount0Delta));
        //        }
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
    function _swapAndBurn(
        RecoveryLib.RecoveryStorage storage $,
        address targetPool,
        address asset,
        uint assetThreshold
    ) internal returns (uint amount) {
        // assume here that recovery tokens are always set as token 0
        address recoveryToken = IUniswapV3Pool(targetPool).token0();

        // we cannot use swapper here because we need to limit result price by SQRT_PRICE_LIMIT_X96
        // IERC20(asset).approve(address(swapper_), amount);
        // swapper_.swap(asset, recoveryToken, amount, 20_000);
        uint amountToSwap = IERC20(asset).balanceOf(address(this));
        if (amountToSwap > assetThreshold) {
            _swapToRecoveryToken(targetPool, asset, amountToSwap);
            uint balance = IERC20(recoveryToken).balanceOf(address(this));
            if (balance != 0) {
                address receiver = $.receivers[recoveryToken];
                if (receiver == address(0)) {
                    IBurnableERC20(recoveryToken).burn(balance);
                } else {
                    IERC20(recoveryToken).safeTransfer(receiver, balance);
                }
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

        uint160 currentSqrtPriceX96 = getCurrentSqrtPriceX96(pool_);
        address token0 = IUniswapV3Pool(pool_).token0();
        uint160 sqrtPriceLimitX96 = _sqrtPriceLimitX96(token0, IUniswapV3Pool(pool_).token1());

        if (currentSqrtPriceX96 < sqrtPriceLimitX96) {
            bool zeroForOne = token0 == tokenIn;

            $.swapping = true;

            try IUniswapV3Pool(pool_)
                .swap(
                    address(this), // recipient
                    zeroForOne,
                    int(amountInMax), // exactInput
                    sqrtPriceLimitX96, // sqrtPriceLimitX96
                    "" // data
                ) returns (
                int amount0, int amount1
            ) {
                $.swapping = false;

                uint amountOut = zeroForOne ? uint(-amount1) : uint(-amount0);
                uint amountIn = zeroForOne ? uint(amount0) : uint(amount1);
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

    function _getRecoveryPool(
        address[] memory _recoveryPools,
        uint indexRecoveryPool1
    ) internal view returns (uint index0) {
        require(indexRecoveryPool1 <= _recoveryPools.length, WrongRecoveryPoolIndex());
        return indexRecoveryPool1 == 0 ? selectPool(block.timestamp, _recoveryPools) : indexRecoveryPool1 - 1;
    }

    /// @return index of {value} in {array} or type(uint).max if not found
    function _findItemInArray(address[] memory array, address value) internal pure returns (uint index) {
        for (uint i; i < array.length; ++i) {
            if (array[i] == value) {
                return i;
            }
        }
        return type(uint).max;
    }

    /// @notice Return a new array with the same items as {array} but in random order
    /// @dev We need to shuffle pools because of the following reason.
    /// The algo of filling is following: randomly select first pool, fill it, then fill next and so on
    /// There are 2 pools with metaS and 4 pools with metaUSD.
    /// If we won't shuffle items then the second metaS poll will be filled more rarely then first one.
    /// @param array Original list of recovery pools
    /// @param index1 1-based index of the pool that should be selected first (if 0 then the pool will be selected randomly)
    /// @return shuffled New list of recovery pools in random order
    /// @return newIndex1 Updated 1-based index for the array[index1-1] pool in the shuffled array
    function _getShuffledArray(address[] memory array, uint index1) internal view returns (address[] memory, uint) {
        uint len = array.length;
        address selectedPool = index1 == 0 || index1 >= len ? address(0) : array[index1 - 1];

        LibPRNG.PRNG memory prng;
        LibPRNG.seed(prng, block.number);

        uint[] memory indices = new uint[](len);
        for (uint i; i < len; ++i) {
            indices[i] = i;
        }

        LibPRNG.shuffle(prng, indices);

        address[] memory shuffled = new address[](len);
        for (uint i; i < len; ++i) {
            shuffled[i] = array[indices[i]];
            if (shuffled[i] == selectedPool) {
                index1 = i + 1;
            }
        }

        return (shuffled, index1);
    }

    //endregion -------------------------------------- Utils
}
