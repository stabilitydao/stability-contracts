// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../libs/UniswapV3MathLib.sol";
import "../../core/libs/CommonLib.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IStrategy.sol";
import "../../interfaces/IFarmingStrategy.sol";
import "../../interfaces/IAmmAdapter.sol";
import "../../integrations/uniswapv3/IUniswapV3Pool.sol";
import "../../integrations/uniswapv3/IQuoter.sol";
import "../../integrations/retro/IOToken.sol";

/// @title Library for IRMF strategy code splitting
library IRMFLib {
    /// @custom:storage-location erc7201:stability.IchiRetroMerklFarmStrategy
    struct IchiRetroMerklFarmStrategyStorage {
        address paymentToken;
        address flashPool;
        address oPool;
        address uToPaymentTokenPool;
        address quoter;
        bool flashOn;
    }

    /// @notice Fetches time-weighted average tick using UniswapV3 dataStorage
    /// @param pool Address of UniswapV3 pool that we want to getTimepoints
    /// @param period Number of seconds in the past to start calculating time-weighted average
    /// @return timeWeightedAverageTick The time-weighted average tick from (block.timestamp - period) to block.timestamp
    function consult(address pool, uint32 period) external view returns (int24 timeWeightedAverageTick) {
        require(period != 0, "BP");

        uint32[] memory secondAgos = new uint32[](2);
        secondAgos[0] = period;
        secondAgos[1] = 0;

        (int56[] memory tickCumulatives,) = IUniswapV3Pool(pool).observe(secondAgos);
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        timeWeightedAverageTick = int24(tickCumulativesDelta / int56(int32(period)));

        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(int32(period)) != 0)) timeWeightedAverageTick--;
    }

    /// @notice Given a tick and a token amount, calculates the amount of token received in exchange
    /// @param tick Tick value used to calculate the quote
    /// @param baseAmount Amount of token to be converted
    /// @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
    /// @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
    /// @return quoteAmount Amount of quoteToken received for baseAmount of baseToken
    function getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) external pure returns (uint quoteAmount) {
        uint160 sqrtRatioX96 = UniswapV3MathLib.getSqrtRatioAtTick(tick);
        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint ratioX192 = uint(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? UniswapV3MathLib.mulDiv(ratioX192, baseAmount, 1 << 192)
                : UniswapV3MathLib.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint ratioX128 = UniswapV3MathLib.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? UniswapV3MathLib.mulDiv(ratioX128, baseAmount, 1 << 128)
                : UniswapV3MathLib.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }

    function generateDescription(
        IFactory.Farm memory farm,
        IAmmAdapter ammAdapter
    ) external view returns (string memory) {
        //slither-disable-next-line calls-loop
        return string.concat(
            "Earn ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(farm.rewardAssets), ", "),
            " on Retro by ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(ammAdapter.poolTokens(farm.pool)), "-"),
            " Ichi Yield IQ strategy ",
            shortAddress(farm.addresses[0])
        );
    }

    function shortAddress(address addr) public pure returns (string memory) {
        bytes memory s = bytes(Strings.toHexString(addr));
        bytes memory shortAddr = new bytes(12);
        shortAddr[0] = "0";
        shortAddr[1] = "x";
        shortAddr[2] = s[2];
        shortAddr[3] = s[3];
        shortAddr[4] = s[4];
        shortAddr[5] = s[5];
        shortAddr[6] = ".";
        shortAddr[7] = ".";
        shortAddr[8] = s[38];
        shortAddr[9] = s[39];
        shortAddr[10] = s[40];
        shortAddr[11] = s[41];
        return string(shortAddr);
    }

    function claimRevenue(
        IStrategy.StrategyBaseStorage storage __$__,
        IFarmingStrategy.FarmingStrategyBaseStorage storage _$_,
        IchiRetroMerklFarmStrategyStorage storage $
    )
        external
        returns (
            address[] memory __assets,
            uint[] memory __amounts,
            address[] memory __rewardAssets,
            uint[] memory __rewardAmounts
        )
    {
        __assets = __$__._assets;
        __amounts = new uint[](2);
        __rewardAssets = _$_._rewardAssets;
        uint rwLen = __rewardAssets.length;
        __rewardAmounts = new uint[](rwLen);

        // should we swap or flash excercise
        address oToken = __rewardAssets[0];
        uint oTokenAmount = balance(oToken);
        address oPool = $.oPool;

        if (oTokenAmount > 0) {
            address uToken = getOtherTokenFromPool(oPool, oToken);

            bool needSwap = _shouldWeSwap(oToken, uToken, oTokenAmount, oPool, $.quoter);

            if (!needSwap) {
                // Get payment token amount needed to exercise oTokens.
                uint amountNeeded = IOToken(oToken).getDiscountedPrice(oTokenAmount);

                // Enter flash loan.
                $.flashOn = true;
                IUniswapV3Pool($.flashPool).flash(address(this), 0, amountNeeded, "");
                __rewardAssets[0] = $.paymentToken;
            }
        }

        for (uint i; i < rwLen; ++i) {
            __rewardAmounts[i] = balance(__rewardAssets[i]);
        }
    }

    function _shouldWeSwap(
        address oToken,
        address uToken,
        uint amount,
        address pool,
        address quoter
    ) internal returns (bool should) {
        // Whats the amount of underlying we get for flashSwapping.
        uint discount = IOToken(oToken).discount();
        uint flashAmount = amount * (100 - discount) / 100;

        // How much we get for just swapping through LP.
        uint24 fee = IUniswapV3Pool(pool).fee();
        uint swapAmount = IQuoter(quoter).quoteExactInputSingle(oToken, uToken, fee, amount, 0);

        if (swapAmount > flashAmount) {
            should = true;
        }
    }

    function getOtherTokenFromPool(address pool, address token) public view returns (address) {
        address token0 = IUniswapV3Pool(pool).token0();
        address token1 = IUniswapV3Pool(pool).token1();
        return token == token0 ? token1 : token0;
    }

    function balance(address token) public view returns (uint) {
        return IERC20(token).balanceOf(address(this));
    }
}
