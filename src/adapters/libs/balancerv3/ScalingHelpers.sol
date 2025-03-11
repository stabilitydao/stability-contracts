// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import {FixedPoint} from "./FixedPoint.sol";

/**
 * @notice Helper functions to apply/undo token decimal and rate adjustments, rounding in the direction indicated.
 * @dev To simplify Pool logic, all token balances and amounts are normalized to behave as if the token had
 * 18 decimals. When comparing DAI (18 decimals) and USDC (6 decimals), 1 USDC and 1 DAI would both be
 * represented as 1e18. This allows us to not consider differences in token decimals in the internal Pool
 * math, simplifying it greatly.
 *
 * The Vault does not support tokens with more than 18 decimals (see `_MAX_TOKEN_DECIMALS` in `VaultStorage`),
 * or tokens that do not implement `IERC20Metadata.decimals`.
 *
 * These helpers can also be used to scale amounts by other 18-decimal floating point values, such as rates.
 */
library ScalingHelpers {
    using FixedPoint for *;

    /**
     * @notice Applies `scalingFactor` and `tokenRate` to `amount`.
     * @dev This may result in a larger or equal value, depending on whether it needed scaling/rate adjustment or not.
     * The result is rounded down.
     *
     * @param amount Amount to be scaled up to 18 decimals
     * @param scalingFactor The token decimal scaling factor, `10^(18-tokenDecimals)`
     * @param tokenRate The token rate scaling factor
     * @return result The final 18-decimal precision result, rounded down
     */
    function toScaled18ApplyRateRoundDown(
        uint amount,
        uint scalingFactor,
        uint tokenRate
    ) internal pure returns (uint) {
        return (amount * scalingFactor).mulDown(tokenRate);
    }

    /**
     * @notice Applies `scalingFactor` and `tokenRate` to `amount`.
     * @dev This may result in a larger or equal value, depending on whether it needed scaling/rate adjustment or not.
     * The result is rounded up.
     *
     * @param amount Amount to be scaled up to 18 decimals
     * @param scalingFactor The token decimal scaling factor, `10^(18-tokenDecimals)`
     * @param tokenRate The token rate scaling factor
     * @return result The final 18-decimal precision result, rounded up
     */
    function toScaled18ApplyRateRoundUp(uint amount, uint scalingFactor, uint tokenRate) internal pure returns (uint) {
        return (amount * scalingFactor).mulUp(tokenRate);
    }

    /**
     * @notice Reverses the `scalingFactor` and `tokenRate` applied to `amount`.
     * @dev This may result in a smaller or equal value, depending on whether it needed scaling/rate adjustment or not.
     * The result is rounded down.
     *
     * @param amount Amount to be scaled down to native token decimals
     * @param scalingFactor The token decimal scaling factor, `10^(18-tokenDecimals)`
     * @param tokenRate The token rate scaling factor
     * @return result The final native decimal result, rounded down
     */
    function toRawUndoRateRoundDown(uint amount, uint scalingFactor, uint tokenRate) internal pure returns (uint) {
        // Do division last. Scaling factor is not a FP18, but a FP18 normalized by FP(1).
        // `scalingFactor * tokenRate` is a precise FP18, so there is no rounding direction here.
        return FixedPoint.divDown(amount, scalingFactor * tokenRate);
    }

    /**
     * @notice Reverses the `scalingFactor` and `tokenRate` applied to `amount`.
     * @dev This may result in a smaller or equal value, depending on whether it needed scaling/rate adjustment or not.
     * The result is rounded up.
     *
     * @param amount Amount to be scaled down to native token decimals
     * @param scalingFactor The token decimal scaling factor, `10^(18-tokenDecimals)`
     * @param tokenRate The token rate scaling factor
     * @return result The final native decimal result, rounded up
     */
    function toRawUndoRateRoundUp(uint amount, uint scalingFactor, uint tokenRate) internal pure returns (uint) {
        // Do division last. Scaling factor is not a FP18, but a FP18 normalized by FP(1).
        // `scalingFactor * tokenRate` is a precise FP18, so there is no rounding direction here.
        return FixedPoint.divUp(amount, scalingFactor * tokenRate);
    }

    /**
     * @notice Rounds up a rate informed by a rate provider.
     * @dev Rates calculated by an external rate provider have rounding errors. Intuitively, a rate provider
     * rounds the rate down so the pool math is executed with conservative amounts. However, when upscaling or
     * downscaling the amount out, the rate should be rounded up to make sure the amounts scaled are conservative.
     * @param rate The original rate
     * @return roundedRate The final rate, with rounding applied
     */
    function computeRateRoundUp(uint rate) internal pure returns (uint) {
        uint roundedRate;
        // If rate is divisible by FixedPoint.ONE, roundedRate and rate will be equal. It means that rate has 18 zeros,
        // so there's no rounding issue and the rate should not be rounded up.
        unchecked {
            roundedRate = (rate / FixedPoint.ONE) * FixedPoint.ONE;
        }
        return roundedRate == rate ? rate : rate + 1;
    }
}
