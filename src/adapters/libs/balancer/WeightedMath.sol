// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "./FixedPoint.sol";
import "./LegacyOZMath.sol";

// These functions start with an underscore, as if they were part of a contract and not a library. At some point this
// should be fixed.
// solhint-disable private-vars-leading-underscore

library WeightedMath {
    using FixedPoint for uint;
    // A minimum normalized weight imposes a maximum weight ratio. We need this due to limitations in the
    // implementation of the power function, as these ratios are often exponents.

    uint internal constant _MIN_WEIGHT = 0.01e18;
    // Having a minimum normalized weight imposes a limit on the maximum number of tokens;
    // i.e., the largest possible pool is one where all tokens have exactly the minimum weight.
    uint internal constant _MAX_WEIGHTED_TOKENS = 100;

    // Pool limits that arise from limitations in the fixed point power function (and the imposed 1:100 maximum weight
    // ratio).

    // Swap limits: amounts swapped may not be larger than this percentage of total balance.
    uint internal constant _MAX_IN_RATIO = 0.3e18;
    uint internal constant _MAX_OUT_RATIO = 0.3e18;

    // Invariant growth limit: non-proportional joins cannot cause the invariant to increase by more than this ratio.
    uint internal constant _MAX_INVARIANT_RATIO = 3e18;
    // Invariant shrink limit: non-proportional exits cannot cause the invariant to decrease by less than this ratio.
    uint internal constant _MIN_INVARIANT_RATIO = 0.7e18;

    // About swap fees on joins and exits:
    // Any join or exit that is not perfectly balanced (e.g. all single token joins or exits) is mathematically
    // equivalent to a perfectly balanced join or  exit followed by a series of swaps. Since these swaps would charge
    // swap fees, it follows that (some) joins and exits should as well.
    // On these operations, we split the token amounts in 'taxable' and 'non-taxable' portions, where the 'taxable' part
    // is the one to which swap fees are applied.

    // Invariant is used to collect protocol swap fees by comparing its value between two times.
    // So we can round always to the same direction. It is also used to initiate the BPT amount
    // and, because there is a minimum BPT, we round down the invariant.
    function _calculateInvariant(
        uint[] memory normalizedWeights,
        uint[] memory balances
    ) internal pure returns (uint invariant) {
        /**
         *
         *     // invariant               _____                                                             //
         *     // wi = weight index i      | |      wi                                                      //
         *     // bi = balance index i     | |  bi ^   = i                                                  //
         *     // i = invariant                                                                             //
         *
         */
        invariant = FixedPoint.ONE;
        for (uint i = 0; i < normalizedWeights.length; i++) {
            invariant = invariant.mulDown(balances[i].powDown(normalizedWeights[i]));
        }

        _require(invariant > 0, Errors.ZERO_INVARIANT);
    }

    // Computes how many tokens can be taken out of a pool if `amountIn` are sent, given the
    // current balances and weights.
    function _calcOutGivenIn(
        uint balanceIn,
        uint weightIn,
        uint balanceOut,
        uint weightOut,
        uint amountIn
    ) internal pure returns (uint) {
        /**
         *
         *     // outGivenIn                                                                                //
         *     // aO = amountOut                                                                            //
         *     // bO = balanceOut                                                                           //
         *     // bI = balanceIn              /      /            bI             \    (wI / wO) \           //
         *     // aI = amountIn    aO = bO * |  1 - | --------------------------  | ^            |          //
         *     // wI = weightIn               \      \       ( bI + aI )         /              /           //
         *     // wO = weightOut                                                                            //
         *
         */

        // Amount out, so we round down overall.

        // The multiplication rounds down, and the subtrahend (power) rounds up (so the base rounds up too).
        // Because bI / (bI + aI) <= 1, the exponent rounds down.

        // Cannot exceed maximum in ratio
        _require(amountIn <= balanceIn.mulDown(_MAX_IN_RATIO), Errors.MAX_IN_RATIO);

        uint denominator = balanceIn.add(amountIn);
        uint base = balanceIn.divUp(denominator);
        uint exponent = weightIn.divDown(weightOut);
        uint power = base.powUp(exponent);

        return balanceOut.mulDown(power.complement());
    }

    // Computes how many tokens must be sent to a pool in order to take `amountOut`, given the
    // current balances and weights.
    function _calcInGivenOut(
        uint balanceIn,
        uint weightIn,
        uint balanceOut,
        uint weightOut,
        uint amountOut
    ) internal pure returns (uint) {
        /**
         *
         *     // inGivenOut                                                                                //
         *     // aO = amountOut                                                                            //
         *     // bO = balanceOut                                                                           //
         *     // bI = balanceIn              /  /            bO             \    (wO / wI)      \          //
         *     // aI = amountIn    aI = bI * |  | --------------------------  | ^            - 1  |         //
         *     // wI = weightIn               \  \       ( bO - aO )         /                   /          //
         *     // wO = weightOut                                                                            //
         *
         */

        // Amount in, so we round up overall.

        // The multiplication rounds up, and the power rounds up (so the base rounds up too).
        // Because b0 / (b0 - a0) >= 1, the exponent rounds up.

        // Cannot exceed maximum out ratio
        _require(amountOut <= balanceOut.mulDown(_MAX_OUT_RATIO), Errors.MAX_OUT_RATIO);

        uint base = balanceOut.divUp(balanceOut.sub(amountOut));
        uint exponent = weightOut.divUp(weightIn);
        uint power = base.powUp(exponent);

        // Because the base is larger than one (and the power rounds up), the power should always be larger than one, so
        // the following subtraction should never revert.
        uint ratio = power.sub(FixedPoint.ONE);

        return balanceIn.mulUp(ratio);
    }

    function _calcBptOutGivenExactTokensIn(
        uint[] memory balances,
        uint[] memory normalizedWeights,
        uint[] memory amountsIn,
        uint bptTotalSupply,
        uint swapFeePercentage
    ) internal pure returns (uint, uint[] memory) {
        // BPT out, so we round down overall.

        uint[] memory balanceRatiosWithFee = new uint[](amountsIn.length);

        uint invariantRatioWithFees = 0;
        for (uint i = 0; i < balances.length; i++) {
            balanceRatiosWithFee[i] = balances[i].add(amountsIn[i]).divDown(balances[i]);
            invariantRatioWithFees = invariantRatioWithFees.add(balanceRatiosWithFee[i].mulDown(normalizedWeights[i]));
        }

        (uint invariantRatio, uint[] memory swapFees) = _computeJoinExactTokensInInvariantRatio(
            balances, normalizedWeights, amountsIn, balanceRatiosWithFee, invariantRatioWithFees, swapFeePercentage
        );

        uint bptOut = (invariantRatio > FixedPoint.ONE) ? bptTotalSupply.mulDown(invariantRatio.sub(FixedPoint.ONE)) : 0;
        return (bptOut, swapFees);
    }

    /**
     * @dev Intermediate function to avoid stack-too-deep errors.
     */
    function _computeJoinExactTokensInInvariantRatio(
        uint[] memory balances,
        uint[] memory normalizedWeights,
        uint[] memory amountsIn,
        uint[] memory balanceRatiosWithFee,
        uint invariantRatioWithFees,
        uint swapFeePercentage
    ) private pure returns (uint invariantRatio, uint[] memory swapFees) {
        // Swap fees are charged on all tokens that are being added in a larger proportion than the overall invariant
        // increase.
        swapFees = new uint[](amountsIn.length);
        invariantRatio = FixedPoint.ONE;

        for (uint i = 0; i < balances.length; i++) {
            uint amountInWithoutFee;

            if (balanceRatiosWithFee[i] > invariantRatioWithFees) {
                uint nonTaxableAmount = balances[i].mulDown(invariantRatioWithFees.sub(FixedPoint.ONE));
                uint taxableAmount = amountsIn[i].sub(nonTaxableAmount);
                uint swapFee = taxableAmount.mulUp(swapFeePercentage);

                amountInWithoutFee = nonTaxableAmount.add(taxableAmount.sub(swapFee));
                swapFees[i] = swapFee;
            } else {
                amountInWithoutFee = amountsIn[i];
            }

            uint balanceRatio = balances[i].add(amountInWithoutFee).divDown(balances[i]);

            invariantRatio = invariantRatio.mulDown(balanceRatio.powDown(normalizedWeights[i]));
        }
    }

    function _calcTokenInGivenExactBptOut(
        uint balance,
        uint normalizedWeight,
        uint bptAmountOut,
        uint bptTotalSupply,
        uint swapFeePercentage
    ) internal pure returns (uint amountIn, uint swapFee) {
        /**
         *
         *     // tokenInForExactBPTOut                                                                 //
         *     // a = amountIn                                                                          //
         *     // b = balance                      /  /    totalBPT + bptOut      \    (1 / w)       \  //
         *     // bptOut = bptAmountOut   a = b * |  | --------------------------  | ^          - 1  |  //
         *     // bpt = totalBPT                   \  \       totalBPT            /                  /  //
         *     // w = weight                                                                            //
         *
         */

        // Token in, so we round up overall.

        // Calculate the factor by which the invariant will increase after minting BPTAmountOut
        uint invariantRatio = bptTotalSupply.add(bptAmountOut).divUp(bptTotalSupply);
        _require(invariantRatio <= _MAX_INVARIANT_RATIO, Errors.MAX_OUT_BPT_FOR_TOKEN_IN);

        // Calculate by how much the token balance has to increase to match the invariantRatio
        uint balanceRatio = invariantRatio.powUp(FixedPoint.ONE.divUp(normalizedWeight));

        uint amountInWithoutFee = balance.mulUp(balanceRatio.sub(FixedPoint.ONE));

        // We can now compute how much extra balance is being deposited and used in virtual swaps, and charge swap fees
        // accordingly.
        uint taxablePercentage = normalizedWeight.complement();
        uint taxableAmount = amountInWithoutFee.mulUp(taxablePercentage);
        uint nonTaxableAmount = amountInWithoutFee.sub(taxableAmount);

        uint taxableAmountPlusFees = taxableAmount.divUp(FixedPoint.ONE.sub(swapFeePercentage));

        swapFee = taxableAmountPlusFees - taxableAmount;
        amountIn = nonTaxableAmount.add(taxableAmountPlusFees);
    }

    function _calcAllTokensInGivenExactBptOut(
        uint[] memory balances,
        uint bptAmountOut,
        uint totalBPT
    ) internal pure returns (uint[] memory) {
        /**
         *
         *     // tokensInForExactBptOut                                                          //
         *     // (per token)                                                                     //
         *     // aI = amountIn                   /   bptOut   \                                  //
         *     // b = balance           aI = b * | ------------ |                                 //
         *     // bptOut = bptAmountOut           \  totalBPT  /                                  //
         *     // bpt = totalBPT                                                                  //
         *
         */

        // Tokens in, so we round up overall.
        uint bptRatio = bptAmountOut.divUp(totalBPT);

        uint[] memory amountsIn = new uint[](balances.length);
        for (uint i = 0; i < balances.length; i++) {
            amountsIn[i] = balances[i].mulUp(bptRatio);
        }

        return amountsIn;
    }

    function _calcBptInGivenExactTokensOut(
        uint[] memory balances,
        uint[] memory normalizedWeights,
        uint[] memory amountsOut,
        uint bptTotalSupply,
        uint swapFeePercentage
    ) internal pure returns (uint, uint[] memory) {
        // BPT in, so we round up overall.

        uint[] memory balanceRatiosWithoutFee = new uint[](amountsOut.length);
        uint invariantRatioWithoutFees = 0;
        for (uint i = 0; i < balances.length; i++) {
            balanceRatiosWithoutFee[i] = balances[i].sub(amountsOut[i]).divUp(balances[i]);
            invariantRatioWithoutFees =
                invariantRatioWithoutFees.add(balanceRatiosWithoutFee[i].mulUp(normalizedWeights[i]));
        }

        (uint invariantRatio, uint[] memory swapFees) = _computeExitExactTokensOutInvariantRatio(
            balances,
            normalizedWeights,
            amountsOut,
            balanceRatiosWithoutFee,
            invariantRatioWithoutFees,
            swapFeePercentage
        );

        uint bptIn = bptTotalSupply.mulUp(invariantRatio.complement());
        return (bptIn, swapFees);
    }

    /**
     * @dev Intermediate function to avoid stack-too-deep errors.
     */
    function _computeExitExactTokensOutInvariantRatio(
        uint[] memory balances,
        uint[] memory normalizedWeights,
        uint[] memory amountsOut,
        uint[] memory balanceRatiosWithoutFee,
        uint invariantRatioWithoutFees,
        uint swapFeePercentage
    ) private pure returns (uint invariantRatio, uint[] memory swapFees) {
        swapFees = new uint[](amountsOut.length);
        invariantRatio = FixedPoint.ONE;

        for (uint i = 0; i < balances.length; i++) {
            // Swap fees are typically charged on 'token in', but there is no 'token in' here, so we apply it to
            // 'token out'. This results in slightly larger price impact.

            uint amountOutWithFee;
            if (invariantRatioWithoutFees > balanceRatiosWithoutFee[i]) {
                uint nonTaxableAmount = balances[i].mulDown(invariantRatioWithoutFees.complement());
                uint taxableAmount = amountsOut[i].sub(nonTaxableAmount);
                uint taxableAmountPlusFees = taxableAmount.divUp(FixedPoint.ONE.sub(swapFeePercentage));

                swapFees[i] = taxableAmountPlusFees - taxableAmount;
                amountOutWithFee = nonTaxableAmount.add(taxableAmountPlusFees);
            } else {
                amountOutWithFee = amountsOut[i];
            }

            uint balanceRatio = balances[i].sub(amountOutWithFee).divDown(balances[i]);

            invariantRatio = invariantRatio.mulDown(balanceRatio.powDown(normalizedWeights[i]));
        }
    }

    function _calcTokenOutGivenExactBptIn(
        uint balance,
        uint normalizedWeight,
        uint bptAmountIn,
        uint bptTotalSupply,
        uint swapFeePercentage
    ) internal pure returns (uint amountOut, uint swapFee) {
        /**
         *
         *     // exactBPTInForTokenOut                                                                //
         *     // a = amountOut                                                                        //
         *     // b = balance                     /      /    totalBPT - bptIn       \    (1 / w)  \   //
         *     // bptIn = bptAmountIn    a = b * |  1 - | --------------------------  | ^           |  //
         *     // bpt = totalBPT                  \      \       totalBPT            /             /   //
         *     // w = weight                                                                           //
         *
         */

        // Token out, so we round down overall. The multiplication rounds down, but the power rounds up (so the base
        // rounds up). Because (totalBPT - bptIn) / totalBPT <= 1, the exponent rounds down.

        // Calculate the factor by which the invariant will decrease after burning BPTAmountIn
        uint invariantRatio = bptTotalSupply.sub(bptAmountIn).divUp(bptTotalSupply);
        _require(invariantRatio >= _MIN_INVARIANT_RATIO, Errors.MIN_BPT_IN_FOR_TOKEN_OUT);

        // Calculate by how much the token balance has to decrease to match invariantRatio
        uint balanceRatio = invariantRatio.powUp(FixedPoint.ONE.divDown(normalizedWeight));

        // Because of rounding up, balanceRatio can be greater than one. Using complement prevents reverts.
        uint amountOutWithoutFee = balance.mulDown(balanceRatio.complement());

        // We can now compute how much excess balance is being withdrawn as a result of the virtual swaps, which result
        // in swap fees.
        uint taxablePercentage = normalizedWeight.complement();

        // Swap fees are typically charged on 'token in', but there is no 'token in' here, so we apply it
        // to 'token out'. This results in slightly larger price impact. Fees are rounded up.
        uint taxableAmount = amountOutWithoutFee.mulUp(taxablePercentage);
        uint nonTaxableAmount = amountOutWithoutFee.sub(taxableAmount);

        swapFee = taxableAmount.mulUp(swapFeePercentage);
        amountOut = nonTaxableAmount.add(taxableAmount.sub(swapFee));
    }

    function _calcTokensOutGivenExactBptIn(
        uint[] memory balances,
        uint bptAmountIn,
        uint totalBPT
    ) internal pure returns (uint[] memory) {
        /**
         *
         *     // exactBPTInForTokensOut                                                                    //
         *     // (per token)                                                                               //
         *     // aO = amountOut                  /        bptIn         \                                  //
         *     // b = balance           a0 = b * | ---------------------  |                                 //
         *     // bptIn = bptAmountIn             \       totalBPT       /                                  //
         *     // bpt = totalBPT                                                                            //
         *
         */

        // Since we're computing an amount out, we round down overall. This means rounding down on both the
        // multiplication and division.

        uint bptRatio = bptAmountIn.divDown(totalBPT);

        uint[] memory amountsOut = new uint[](balances.length);
        for (uint i = 0; i < balances.length; i++) {
            amountsOut[i] = balances[i].mulDown(bptRatio);
        }

        return amountsOut;
    }

    function _calcDueTokenProtocolSwapFeeAmount(
        uint balance,
        uint normalizedWeight,
        uint previousInvariant,
        uint currentInvariant,
        uint protocolSwapFeePercentage
    ) internal pure returns (uint) {
        /**
         *
         *     /*  protocolSwapFeePercentage * balanceToken * ( 1 - (previousInvariant / currentInvariant) ^ (1 / weightToken))
         *
         */
        if (currentInvariant <= previousInvariant) {
            // This shouldn't happen outside of rounding errors, but have this safeguard nonetheless to prevent the Pool
            // from entering a locked state in which joins and exits revert while computing accumulated swap fees.
            return 0;
        }

        // We round down to prevent issues in the Pool's accounting, even if it means paying slightly less in protocol
        // fees to the Vault.

        // Fee percentage and balance multiplications round down, while the subtrahend (power) rounds up (as does the
        // base). Because previousInvariant / currentInvariant <= 1, the exponent rounds down.

        uint base = previousInvariant.divUp(currentInvariant);
        uint exponent = FixedPoint.ONE.divDown(normalizedWeight);

        // Because the exponent is larger than one, the base of the power function has a lower bound. We cap to this
        // value to avoid numeric issues, which means in the extreme case (where the invariant growth is larger than
        // 1 / min exponent) the Pool will pay less in protocol fees than it should.
        base = LegacyOZMath.max(base, FixedPoint.MIN_POW_BASE_FREE_EXPONENT);

        uint power = base.powUp(exponent);

        uint tokenAccruedFees = balance.mulDown(power.complement());
        return tokenAccruedFees.mulDown(protocolSwapFeePercentage);
    }
}
