// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "./FixedPoint.sol";
import {LegacyOZMath} from "./LegacyOZMath.sol";

library StableMath {
    using FixedPoint for uint;

    uint internal constant _MIN_AMP = 1;
    uint internal constant _MAX_AMP = 5000;
    uint internal constant _AMP_PRECISION = 1e3;

    uint internal constant _MAX_STABLE_TOKENS = 5;

    // Note on unchecked arithmetic:
    // This contract performs a large number of additions, subtractions, multiplications and divisions, often inside
    // loops. Since many of these operations are gas-sensitive (as they happen e.g. during a swap), it is important to
    // not make any unnecessary checks. We rely on a set of invariants to avoid having to use checked arithmetic (the
    // Math library), including:
    //  - the number of tokens is bounded by _MAX_STABLE_TOKENS
    //  - the amplification parameter is bounded by _MAX_AMP * _AMP_PRECISION, which fits in 23 bits
    //  - the token balances are bounded by 2^112 (guaranteed by the Vault) times 1e18 (the maximum scaling factor),
    //    which fits in 172 bits
    //
    // This means e.g. we can safely multiply a balance by the amplification parameter without worrying about overflow.

    // About swap fees on joins and exits:
    // Any join or exit that is not perfectly balanced (e.g. all single token joins or exits) is mathematically
    // equivalent to a perfectly balanced join or  exit followed by a series of swaps. Since these swaps would charge
    // swap fees, it follows that (some) joins and exits should as well.
    // On these operations, we split the token amounts in 'taxable' and 'non-taxable' portions, where the 'taxable' part
    // is the one to which swap fees are applied.

    // Computes the invariant given the current balances, using the Newton-Raphson approximation.
    // The amplification parameter equals: A n^(n-1)
    function _calculateInvariant(
        uint amplificationParameter,
        uint[] memory balances,
        bool roundUp
    ) internal pure returns (uint) {
        /**
         *
         *     // invariant                                                                                 //
         *     // D = invariant                                                  D^(n+1)                    //
         *     // A = amplification coefficient      A  n^n S + D = A D n^n + -----------                   //
         *     // S = sum of balances                                             n^n P                     //
         *     // P = product of balances                                                                   //
         *     // n = number of tokens                                                                      //
         *
         */

        // We support rounding up or down.

        uint sum = 0;
        uint numTokens = balances.length;
        for (uint i = 0; i < numTokens; i++) {
            sum = sum.add(balances[i]);
        }
        if (sum == 0) {
            return 0;
        }

        uint prevInvariant = 0;
        uint invariant = sum;
        uint ampTimesTotal = amplificationParameter * numTokens;

        for (uint i = 0; i < 255; i++) {
            uint P_D = balances[0] * numTokens;
            for (uint j = 1; j < numTokens; j++) {
                P_D = LegacyOZMath.div(
                    LegacyOZMath.mul(LegacyOZMath.mul(P_D, balances[j]), numTokens), invariant, roundUp
                );
            }
            prevInvariant = invariant;
            invariant = LegacyOZMath.div(
                LegacyOZMath.mul(LegacyOZMath.mul(numTokens, invariant), invariant).add(
                    LegacyOZMath.div(
                        LegacyOZMath.mul(LegacyOZMath.mul(ampTimesTotal, sum), P_D), _AMP_PRECISION, roundUp
                    )
                ),
                LegacyOZMath.mul(numTokens + 1, invariant).add(
                    // No need to use checked arithmetic for the amp precision, the amp is guaranteed to be at least 1
                    LegacyOZMath.div(LegacyOZMath.mul(ampTimesTotal - _AMP_PRECISION, P_D), _AMP_PRECISION, !roundUp)
                ),
                roundUp
            );

            if (invariant > prevInvariant) {
                if (invariant - prevInvariant <= 1) {
                    return invariant;
                }
            } else if (prevInvariant - invariant <= 1) {
                return invariant;
            }
        }

        _revert(Errors.STABLE_INVARIANT_DIDNT_CONVERGE);
    }

    // Computes how many tokens can be taken out of a pool if `tokenAmountIn` are sent, given the current balances.
    // The amplification parameter equals: A n^(n-1)
    // The invariant should be rounded up.
    function _calcOutGivenIn(
        uint amplificationParameter,
        uint[] memory balances,
        uint tokenIndexIn,
        uint tokenIndexOut,
        uint tokenAmountIn,
        uint invariant
    ) internal pure returns (uint) {
        /**
         *
         *     // outGivenIn token x for y - polynomial equation to solve                                                   //
         *     // ay = amount out to calculate                                                                              //
         *     // by = balance token out                                                                                    //
         *     // y = by - ay (finalBalanceOut)                                                                             //
         *     // D = invariant                                               D                     D^(n+1)                 //
         *     // A = amplification coefficient               y^2 + ( S - ----------  - D) * y -  ------------- = 0         //
         *     // n = number of tokens                                    (A * n^n)               A * n^2n * P              //
         *     // S = sum of final balances but y                                                                           //
         *     // P = product of final balances but y                                                                       //
         *
         */

        // Amount out, so we round down overall.
        balances[tokenIndexIn] = balances[tokenIndexIn].add(tokenAmountIn);

        uint finalBalanceOut = _getTokenBalanceGivenInvariantAndAllOtherBalances(
            amplificationParameter, balances, invariant, tokenIndexOut
        );

        // No need to use checked arithmetic since `tokenAmountIn` was actually added to the same balance right before
        // calling `_getTokenBalanceGivenInvariantAndAllOtherBalances` which doesn't alter the balances array.
        balances[tokenIndexIn] = balances[tokenIndexIn] - tokenAmountIn;

        return balances[tokenIndexOut].sub(finalBalanceOut).sub(1);
    }

    // Computes how many tokens must be sent to a pool if `tokenAmountOut` are sent given the
    // current balances, using the Newton-Raphson approximation.
    // The amplification parameter equals: A n^(n-1)
    // The invariant should be rounded up.
    function _calcInGivenOut(
        uint amplificationParameter,
        uint[] memory balances,
        uint tokenIndexIn,
        uint tokenIndexOut,
        uint tokenAmountOut,
        uint invariant
    ) internal pure returns (uint) {
        /**
         *
         *     // inGivenOut token x for y - polynomial equation to solve                                                   //
         *     // ax = amount in to calculate                                                                               //
         *     // bx = balance token in                                                                                     //
         *     // x = bx + ax (finalBalanceIn)                                                                              //
         *     // D = invariant                                                D                     D^(n+1)                //
         *     // A = amplification coefficient               x^2 + ( S - ----------  - D) * x -  ------------- = 0         //
         *     // n = number of tokens                                     (A * n^n)               A * n^2n * P             //
         *     // S = sum of final balances but x                                                                           //
         *     // P = product of final balances but x                                                                       //
         *
         */

        // Amount in, so we round up overall.
        balances[tokenIndexOut] = balances[tokenIndexOut].sub(tokenAmountOut);

        uint finalBalanceIn =
            _getTokenBalanceGivenInvariantAndAllOtherBalances(amplificationParameter, balances, invariant, tokenIndexIn);

        // No need to use checked arithmetic since `tokenAmountOut` was actually subtracted from the same balance right
        // before calling `_getTokenBalanceGivenInvariantAndAllOtherBalances` which doesn't alter the balances array.
        balances[tokenIndexOut] = balances[tokenIndexOut] + tokenAmountOut;

        return finalBalanceIn.sub(balances[tokenIndexIn]).add(1);
    }

    function _calcBptOutGivenExactTokensIn(
        uint amp,
        uint[] memory balances,
        uint[] memory amountsIn,
        uint bptTotalSupply,
        uint swapFeePercentage
    ) internal pure returns (uint) {
        // BPT out, so we round down overall.

        // First loop calculates the sum of all token balances, which will be used to calculate
        // the current weights of each token, relative to this sum
        uint sumBalances = 0;
        for (uint i = 0; i < balances.length; i++) {
            sumBalances = sumBalances.add(balances[i]);
        }

        // Calculate the weighted balance ratio without considering fees
        uint[] memory balanceRatiosWithFee = new uint[](amountsIn.length);
        // The weighted sum of token balance ratios with fee
        uint invariantRatioWithFees = 0;
        for (uint i = 0; i < balances.length; i++) {
            uint currentWeight = balances[i].divDown(sumBalances);
            balanceRatiosWithFee[i] = balances[i].add(amountsIn[i]).divDown(balances[i]);
            invariantRatioWithFees = invariantRatioWithFees.add(balanceRatiosWithFee[i].mulDown(currentWeight));
        }

        // Second loop calculates new amounts in, taking into account the fee on the percentage excess
        uint[] memory newBalances = new uint[](balances.length);
        for (uint i = 0; i < balances.length; i++) {
            uint amountInWithoutFee;

            // Check if the balance ratio is greater than the ideal ratio to charge fees or not
            if (balanceRatiosWithFee[i] > invariantRatioWithFees) {
                uint nonTaxableAmount = balances[i].mulDown(invariantRatioWithFees.sub(FixedPoint.ONE));
                uint taxableAmount = amountsIn[i].sub(nonTaxableAmount);
                // No need to use checked arithmetic for the swap fee, it is guaranteed to be lower than 50%
                amountInWithoutFee = nonTaxableAmount.add(taxableAmount.mulDown(FixedPoint.ONE - swapFeePercentage));
            } else {
                amountInWithoutFee = amountsIn[i];
            }

            newBalances[i] = balances[i].add(amountInWithoutFee);
        }

        // Get current and new invariants, taking swap fees into account
        uint currentInvariant = _calculateInvariant(amp, balances, true);
        uint newInvariant = _calculateInvariant(amp, newBalances, false);
        uint invariantRatio = newInvariant.divDown(currentInvariant);

        // If the invariant didn't increase for any reason, we simply don't mint BPT
        if (invariantRatio > FixedPoint.ONE) {
            return bptTotalSupply.mulDown(invariantRatio - FixedPoint.ONE);
        } else {
            return 0;
        }
    }

    function _calcTokenInGivenExactBptOut(
        uint amp,
        uint[] memory balances,
        uint tokenIndex,
        uint bptAmountOut,
        uint bptTotalSupply,
        uint swapFeePercentage
    ) internal pure returns (uint) {
        // Token in, so we round up overall.

        // Get the current invariant
        uint currentInvariant = _calculateInvariant(amp, balances, true);

        // Calculate new invariant
        uint newInvariant = bptTotalSupply.add(bptAmountOut).divUp(bptTotalSupply).mulUp(currentInvariant);

        // Calculate amount in without fee.
        uint newBalanceTokenIndex =
            _getTokenBalanceGivenInvariantAndAllOtherBalances(amp, balances, newInvariant, tokenIndex);
        uint amountInWithoutFee = newBalanceTokenIndex.sub(balances[tokenIndex]);

        // First calculate the sum of all token balances, which will be used to calculate
        // the current weight of each token
        uint sumBalances = 0;
        for (uint i = 0; i < balances.length; i++) {
            sumBalances = sumBalances.add(balances[i]);
        }

        // We can now compute how much extra balance is being deposited and used in virtual swaps, and charge swap fees
        // accordingly.
        uint currentWeight = balances[tokenIndex].divDown(sumBalances);
        uint taxablePercentage = currentWeight.complement();
        uint taxableAmount = amountInWithoutFee.mulUp(taxablePercentage);
        uint nonTaxableAmount = amountInWithoutFee.sub(taxableAmount);

        // No need to use checked arithmetic for the swap fee, it is guaranteed to be lower than 50%
        return nonTaxableAmount.add(taxableAmount.divUp(FixedPoint.ONE - swapFeePercentage));
    }

    /*
    Flow of calculations:
    amountsTokenOut -> amountsOutProportional ->
    amountOutPercentageExcess -> amountOutBeforeFee -> newInvariant -> amountBPTIn
    */
    function _calcBptInGivenExactTokensOut(
        uint amp,
        uint[] memory balances,
        uint[] memory amountsOut,
        uint bptTotalSupply,
        uint swapFeePercentage
    ) internal pure returns (uint) {
        // BPT in, so we round up overall.

        // First loop calculates the sum of all token balances, which will be used to calculate
        // the current weights of each token relative to this sum
        uint sumBalances = 0;
        for (uint i = 0; i < balances.length; i++) {
            sumBalances = sumBalances.add(balances[i]);
        }

        // Calculate the weighted balance ratio without considering fees
        uint[] memory balanceRatiosWithoutFee = new uint[](amountsOut.length);
        uint invariantRatioWithoutFees = 0;
        for (uint i = 0; i < balances.length; i++) {
            uint currentWeight = balances[i].divUp(sumBalances);
            balanceRatiosWithoutFee[i] = balances[i].sub(amountsOut[i]).divUp(balances[i]);
            invariantRatioWithoutFees = invariantRatioWithoutFees.add(balanceRatiosWithoutFee[i].mulUp(currentWeight));
        }

        // Second loop calculates new amounts in, taking into account the fee on the percentage excess
        uint[] memory newBalances = new uint[](balances.length);
        for (uint i = 0; i < balances.length; i++) {
            // Swap fees are typically charged on 'token in', but there is no 'token in' here, so we apply it to
            // 'token out'. This results in slightly larger price impact.

            uint amountOutWithFee;
            if (invariantRatioWithoutFees > balanceRatiosWithoutFee[i]) {
                uint nonTaxableAmount = balances[i].mulDown(invariantRatioWithoutFees.complement());
                uint taxableAmount = amountsOut[i].sub(nonTaxableAmount);
                // No need to use checked arithmetic for the swap fee, it is guaranteed to be lower than 50%
                amountOutWithFee = nonTaxableAmount.add(taxableAmount.divUp(FixedPoint.ONE - swapFeePercentage));
            } else {
                amountOutWithFee = amountsOut[i];
            }

            newBalances[i] = balances[i].sub(amountOutWithFee);
        }

        // Get current and new invariants, taking into account swap fees
        uint currentInvariant = _calculateInvariant(amp, balances, true);
        uint newInvariant = _calculateInvariant(amp, newBalances, false);
        uint invariantRatio = newInvariant.divDown(currentInvariant);

        // return amountBPTIn
        return bptTotalSupply.mulUp(invariantRatio.complement());
    }

    function _calcTokenOutGivenExactBptIn(
        uint amp,
        uint[] memory balances,
        uint tokenIndex,
        uint bptAmountIn,
        uint bptTotalSupply,
        uint swapFeePercentage
    ) internal pure returns (uint) {
        // Token out, so we round down overall.

        // Get the current and new invariants. Since we need a bigger new invariant, we round the current one up.
        uint currentInvariant = _calculateInvariant(amp, balances, true);
        uint newInvariant = bptTotalSupply.sub(bptAmountIn).divUp(bptTotalSupply).mulUp(currentInvariant);

        // Calculate amount out without fee
        uint newBalanceTokenIndex =
            _getTokenBalanceGivenInvariantAndAllOtherBalances(amp, balances, newInvariant, tokenIndex);
        uint amountOutWithoutFee = balances[tokenIndex].sub(newBalanceTokenIndex);

        // First calculate the sum of all token balances, which will be used to calculate
        // the current weight of each token
        uint sumBalances = 0;
        for (uint i = 0; i < balances.length; i++) {
            sumBalances = sumBalances.add(balances[i]);
        }

        // We can now compute how much excess balance is being withdrawn as a result of the virtual swaps, which result
        // in swap fees.
        uint currentWeight = balances[tokenIndex].divDown(sumBalances);
        uint taxablePercentage = currentWeight.complement();

        // Swap fees are typically charged on 'token in', but there is no 'token in' here, so we apply it
        // to 'token out'. This results in slightly larger price impact. Fees are rounded up.
        uint taxableAmount = amountOutWithoutFee.mulUp(taxablePercentage);
        uint nonTaxableAmount = amountOutWithoutFee.sub(taxableAmount);

        // No need to use checked arithmetic for the swap fee, it is guaranteed to be lower than 50%
        return nonTaxableAmount.add(taxableAmount.mulDown(FixedPoint.ONE - swapFeePercentage));
    }

    function _calcTokensOutGivenExactBptIn(
        uint[] memory balances,
        uint bptAmountIn,
        uint bptTotalSupply
    ) internal pure returns (uint[] memory) {
        /**
         *
         *     // exactBPTInForTokensOut                                                                    //
         *     // (per token)                                                                               //
         *     // aO = tokenAmountOut             /        bptIn         \                                  //
         *     // b = tokenBalance      a0 = b * | ---------------------  |                                 //
         *     // bptIn = bptAmountIn             \     bptTotalSupply    /                                 //
         *     // bpt = bptTotalSupply                                                                      //
         *
         */

        // Since we're computing an amount out, we round down overall. This means rounding down on both the
        // multiplication and division.

        uint bptRatio = bptAmountIn.divDown(bptTotalSupply);

        uint[] memory amountsOut = new uint[](balances.length);
        for (uint i = 0; i < balances.length; i++) {
            amountsOut[i] = balances[i].mulDown(bptRatio);
        }

        return amountsOut;
    }

    // The amplification parameter equals: A n^(n-1)
    function _calcDueTokenProtocolSwapFeeAmount(
        uint amplificationParameter,
        uint[] memory balances,
        uint lastInvariant,
        uint tokenIndex,
        uint protocolSwapFeePercentage
    ) internal pure returns (uint) {
        /**
         *
         *     // oneTokenSwapFee - polynomial equation to solve                                                            //
         *     // af = fee amount to calculate in one token                                                                 //
         *     // bf = balance of fee token                                                                                 //
         *     // f = bf - af (finalBalanceFeeToken)                                                                        //
         *     // D = old invariant                                            D                     D^(n+1)                //
         *     // A = amplification coefficient               f^2 + ( S - ----------  - D) * f -  ------------- = 0         //
         *     // n = number of tokens                                    (A * n^n)               A * n^2n * P              //
         *     // S = sum of final balances but f                                                                           //
         *     // P = product of final balances but f                                                                       //
         *
         */

        // Protocol swap fee amount, so we round down overall.

        uint finalBalanceFeeToken = _getTokenBalanceGivenInvariantAndAllOtherBalances(
            amplificationParameter, balances, lastInvariant, tokenIndex
        );

        if (balances[tokenIndex] <= finalBalanceFeeToken) {
            // This shouldn't happen outside of rounding errors, but have this safeguard nonetheless to prevent the Pool
            // from entering a locked state in which joins and exits revert while computing accumulated swap fees.
            return 0;
        }

        // Result is rounded down
        uint accumulatedTokenSwapFees = balances[tokenIndex] - finalBalanceFeeToken;
        return accumulatedTokenSwapFees.mulDown(protocolSwapFeePercentage);
    }

    // Private functions

    // This function calculates the balance of a given token (tokenIndex)
    // given all the other balances and the invariant
    function _getTokenBalanceGivenInvariantAndAllOtherBalances(
        uint amplificationParameter,
        uint[] memory balances,
        uint invariant,
        uint tokenIndex
    ) internal pure returns (uint) {
        // Rounds result up overall

        uint ampTimesTotal = amplificationParameter * balances.length;
        uint sum = balances[0];
        uint P_D = balances[0] * balances.length;
        for (uint j = 1; j < balances.length; j++) {
            P_D = LegacyOZMath.divDown(LegacyOZMath.mul(LegacyOZMath.mul(P_D, balances[j]), balances.length), invariant);
            sum = sum.add(balances[j]);
        }
        // No need to use safe math, based on the loop above `sum` is greater than or equal to `balances[tokenIndex]`
        sum = sum - balances[tokenIndex];

        uint inv2 = LegacyOZMath.mul(invariant, invariant);
        // We remove the balance from c by multiplying it
        uint c = LegacyOZMath.mul(
            LegacyOZMath.mul(LegacyOZMath.divUp(inv2, LegacyOZMath.mul(ampTimesTotal, P_D)), _AMP_PRECISION),
            balances[tokenIndex]
        );
        uint b = sum.add(LegacyOZMath.mul(LegacyOZMath.divDown(invariant, ampTimesTotal), _AMP_PRECISION));

        // We iterate to find the balance
        uint prevTokenBalance = 0;
        // We multiply the first iteration outside the loop with the invariant to set the value of the
        // initial approximation.
        uint tokenBalance = LegacyOZMath.divUp(inv2.add(c), invariant.add(b));

        for (uint i = 0; i < 255; i++) {
            prevTokenBalance = tokenBalance;

            tokenBalance = LegacyOZMath.divUp(
                LegacyOZMath.mul(tokenBalance, tokenBalance).add(c),
                LegacyOZMath.mul(tokenBalance, 2).add(b).sub(invariant)
            );

            if (tokenBalance > prevTokenBalance) {
                if (tokenBalance - prevTokenBalance <= 1) {
                    return tokenBalance;
                }
            } else if (prevTokenBalance - tokenBalance <= 1) {
                return tokenBalance;
            }
        }

        _revert(Errors.STABLE_GET_BALANCE_DIDNT_CONVERGE);
    }
}
