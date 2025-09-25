// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import {FixedPoint, _require, Errors} from "./FixedPoint.sol";

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
    // function _calculateInvariant(
    //     uint[] memory normalizedWeights,
    //     uint[] memory balances
    // ) internal pure returns (uint invariant) {
    //     /**
    //      *
    //      *     // invariant               _____                                                             //
    //      *     // wi = weight index i      | |      wi                                                      //
    //      *     // bi = balance index i     | |  bi ^   = i                                                  //
    //      *     // i = invariant                                                                             //
    //      *
    //      */
    //     invariant = FixedPoint.ONE;
    //     for (uint i = 0; i < normalizedWeights.length; i++) {
    //         invariant = invariant.mulDown(balances[i].powDown(normalizedWeights[i]));
    //     }

    //     _require(invariant > 0, Errors.ZERO_INVARIANT);
    // }

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
}
