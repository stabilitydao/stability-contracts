// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository <https://github.com/gyrostable/concentrated-lps>.
pragma solidity ^0.8.23;
pragma experimental ABIEncoderV2;

// import "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";
import "./GyroFixedPoint.sol";
import "./GyroErrors.sol";
import "./SignedFixedPoint.sol";
import "./GyroPoolMath.sol";
import "./GyroECLPPoolErrors.sol";
import "./balancer-labs-v2-solidity-utils/math/BalancerMath.sol";
import "./balancer-labs-v2-solidity-utils/helpers/InputHelpers.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

// solhint-disable private-vars-leading-underscore

/**
 * @dev ECLP math library. Pretty much a direct translation of the python version (see `tests/`).
 * We use *signed* values here because some of the intermediate results can be negative (e.g. coordinates of points in
 * the untransformed circle, "prices" in the untransformed circle).
 */
library GyroECLPMath {
    uint internal constant ONEHALF = 0.5e18;
    int internal constant ONE = 1e18; // 18 decimal places
    int internal constant ONE_XP = 1e38; // 38 decimal places

    using SignedFixedPoint for int;
    using GyroFixedPoint for uint;
    using SafeCast for uint;
    using SafeCast for int;

    // Anti-overflow limits: Params and DerivedParams (static, only needs to be checked on pool creation)
    int internal constant _ROTATION_VECTOR_NORM_ACCURACY = 1e3; // 1e-15 in normal precision
    int internal constant _MAX_STRETCH_FACTOR = 1e26; // 1e8   in normal precision
    int internal constant _DERIVED_TAU_NORM_ACCURACY_XP = 1e23; // 1e-15 in extra precision
    int internal constant _MAX_INV_INVARIANT_DENOMINATOR_XP = 1e43; // 1e5   in extra precision
    int internal constant _DERIVED_DSQ_NORM_ACCURACY_XP = 1e23; // 1e-15 in extra precision

    // Anti-overflow limits: Dynamic values (checked before operations that use them)
    int internal constant _MAX_BALANCES = 1e34; // 1e16 in normal precision
    int internal constant _MAX_INVARIANT = 3e37; // 3e19 in normal precision

    // Note that all t values (not tp or tpp) could consist of uint's, as could all Params. But it's complicated to
    // convert all the time, so we make them all signed. We also store all intermediate values signed. An exception are
    // the functions that are used by the contract b/c there the values are stored unsigned.
    struct Params {
        // Price bounds (lower and upper). 0 < alpha < beta
        int alpha;
        int beta;
        // Rotation vector:
        // phi in (-90 degrees, 0] is the implicit rotation vector. It's stored as a point:
        int c; // c = cos(-phi) >= 0. rounded to 18 decimals
        int s; //  s = sin(-phi) >= 0. rounded to 18 decimals
        // Invariant: c^2 + s^2 == 1, i.e., the point (c, s) is normalized.
        // due to rounding, this may not = 1. The term dSq in DerivedParams corrects for this in extra precision

        // Stretching factor:
        int lambda; // lambda >= 1 where lambda == 1 is the circle.
    }

    // terms in this struct are stored in extra precision (38 decimals) with final decimal rounded down
    struct DerivedParams {
        Vector2 tauAlpha;
        Vector2 tauBeta;
        int u; // from (A chi)_y = lambda * u + v
        int v; // from (A chi)_y = lambda * u + v
        int w; // from (A chi)_x = w / lambda + z
        int z; // from (A chi)_x = w / lambda + z
        int dSq; // error in c^2 + s^2 = dSq, used to correct errors in c, s, tau, u,v,w,z calculations
            //int256 dAlpha; // normalization constant for tau(alpha)
            //int256 dBeta; // normalization constant for tau(beta)
    }

    struct Vector2 {
        int x;
        int y;
    }

    struct QParams {
        int a;
        int b;
        int c;
    }

    /**
     * @dev Enforces limits and approximate normalization of the rotation vector.
     */
    function validateParams(Params memory params) internal pure {
        _grequire(0 <= params.s && params.s <= ONE, GyroECLPPoolErrors.ROTATION_VECTOR_WRONG);
        _grequire(0 <= params.c && params.c <= ONE, GyroECLPPoolErrors.ROTATION_VECTOR_WRONG);

        Vector2 memory sc = Vector2(params.s, params.c);
        int scnorm2 = scalarProd(sc, sc); // squared norm
        _grequire(
            ONE - _ROTATION_VECTOR_NORM_ACCURACY <= scnorm2 && scnorm2 <= ONE + _ROTATION_VECTOR_NORM_ACCURACY,
            GyroECLPPoolErrors.ROTATION_VECTOR_NOT_NORMALIZED
        );

        _grequire(
            0 <= params.lambda && params.lambda <= _MAX_STRETCH_FACTOR, GyroECLPPoolErrors.STRETCHING_FACTOR_WRONG
        );
    }

    /**
     * @dev Enforces limits and approximate normalization of the derived values.
     * Does NOT check for internal consistency of 'derived' with 'params'.
     */
    function validateDerivedParamsLimits(Params memory params, DerivedParams memory derived) external pure {
        int norm2;
        norm2 = scalarProdXp(derived.tauAlpha, derived.tauAlpha);
        _grequire(
            ONE_XP - _DERIVED_TAU_NORM_ACCURACY_XP <= norm2 && norm2 <= ONE_XP + _DERIVED_TAU_NORM_ACCURACY_XP,
            GyroECLPPoolErrors.DERIVED_TAU_NOT_NORMALIZED
        );
        norm2 = scalarProdXp(derived.tauBeta, derived.tauBeta);
        _grequire(
            ONE_XP - _DERIVED_TAU_NORM_ACCURACY_XP <= norm2 && norm2 <= ONE_XP + _DERIVED_TAU_NORM_ACCURACY_XP,
            GyroECLPPoolErrors.DERIVED_TAU_NOT_NORMALIZED
        );

        _grequire(derived.u <= ONE_XP, GyroECLPPoolErrors.DERIVED_UVWZ_WRONG);
        _grequire(derived.v <= ONE_XP, GyroECLPPoolErrors.DERIVED_UVWZ_WRONG);
        _grequire(derived.w <= ONE_XP, GyroECLPPoolErrors.DERIVED_UVWZ_WRONG);
        _grequire(derived.z <= ONE_XP, GyroECLPPoolErrors.DERIVED_UVWZ_WRONG);

        _grequire(
            ONE_XP - _DERIVED_DSQ_NORM_ACCURACY_XP <= derived.dSq
                && derived.dSq <= ONE_XP + _DERIVED_DSQ_NORM_ACCURACY_XP,
            GyroECLPPoolErrors.DERIVED_DSQ_WRONG
        );

        // NB No anti-overflow checks are required given the checks done above and in validateParams().
        int mulDenominator = ONE_XP.divXpU(calcAChiAChiInXp(params, derived) - ONE_XP);
        _grequire(mulDenominator <= _MAX_INV_INVARIANT_DENOMINATOR_XP, GyroECLPPoolErrors.INVARIANT_DENOMINATOR_WRONG);
    }

    function scalarProd(Vector2 memory t1, Vector2 memory t2) internal pure returns (int ret) {
        ret = t1.x.mulDownMag(t2.x).add(t1.y.mulDownMag(t2.y));
    }

    /// @dev scalar product for extra-precision values
    function scalarProdXp(Vector2 memory t1, Vector2 memory t2) internal pure returns (int ret) {
        ret = t1.x.mulXp(t2.x).add(t1.y.mulXp(t2.y));
    }

    // "Methods" for Params. We could put these into a separate library and import them via 'using' to get method call
    // syntax.

    /**
     * @dev Calculate A t where A is given in Section 2.2
     *  This is reversing rotation and scaling of the ellipse (mapping back to circle)
     */
    function mulA(Params memory params, Vector2 memory tp) internal pure returns (Vector2 memory t) {
        // NB: This function is only used inside calculatePrice(). This is why we can make two simplifications:
        // 1. We don't correct for precision of s, c using d.dSq because that level of precision is not important in this context.
        // 2. We don't need to check for over/underflow b/c these are impossible in that context and given the (checked) assumptions on the various values.
        t.x = params.c.mulDownMagU(tp.x).divDownMagU(params.lambda)
            - params.s.mulDownMagU(tp.y).divDownMagU(params.lambda);
        t.y = params.s.mulDownMagU(tp.x) + params.c.mulDownMagU(tp.y);
    }

    /**
     * @dev Calculate virtual offset a given invariant r.
     *  See calculation in Section 2.1.2 Computing reserve offsets
     *  Note that, in contrast to virtual reserve offsets in CPMM, these are *subtracted* from the real
     *  reserves, moving the curve to the upper-right. They can be positive or negative, but not both can be negative.
     *  Calculates a = r*(A^{-1}tau(beta))_x rounding up in signed direction
     *  Notice that error in r is scaled by lambda, and so rounding direction is important
     */
    function virtualOffset0(
        Params memory p,
        DerivedParams memory d,
        Vector2 memory r // overestimate in x component, underestimate in y
    ) internal pure returns (int a) {
        // a = r lambda c tau(beta)_x + rs tau(beta)_y
        //       account for 1 factors of dSq (2 s,c factors)
        int termXp = d.tauBeta.x.divXpU(d.dSq);
        a = d.tauBeta.x > 0
            ? r.x.mulUpMagU(p.lambda).mulUpMagU(p.c).mulUpXpToNpU(termXp)
            : r.y.mulDownMagU(p.lambda).mulDownMagU(p.c).mulUpXpToNpU(termXp);

        // use fact that tau(beta)_y > 0, so the required rounding direction is clear.
        a = a + r.x.mulUpMagU(p.s).mulUpXpToNpU(d.tauBeta.y.divXpU(d.dSq));
    }

    /**
     * @dev calculate virtual offset b given invariant r.
     *  Calculates b = r*(A^{-1}tau(alpha))_y rounding up in signed direction
     */
    function virtualOffset1(
        Params memory p,
        DerivedParams memory d,
        Vector2 memory r // overestimate in x component, underestimate in y
    ) internal pure returns (int b) {
        // b = -r \lambda s tau(alpha)_x + rc tau(alpha)_y
        //       account for 1 factors of dSq (2 s,c factors)
        int termXp = d.tauAlpha.x.divXpU(d.dSq);
        b = (d.tauAlpha.x < 0)
            ? r.x.mulUpMagU(p.lambda).mulUpMagU(p.s).mulUpXpToNpU(-termXp)
            : (-r.y).mulDownMagU(p.lambda).mulDownMagU(p.s).mulUpXpToNpU(termXp);

        // use fact that tau(alpha)_y > 0, so the required rounding direction is clear.
        b = b + r.x.mulUpMagU(p.c).mulUpXpToNpU(d.tauAlpha.y.divXpU(d.dSq));
    }

    /**
     * Maximal value for the real reserves x when the respective other balance is 0 for given invariant
     *  See calculation in Section 2.1.2. Calculation is ordered here for precision, but error in r is magnified by lambda
     *  Rounds down in signed direction
     */
    function maxBalances0(
        Params memory p,
        DerivedParams memory d,
        Vector2 memory r // overestimate in x-component, underestimate in y-component
    ) internal pure returns (int xp) {
        // x^+ = r lambda c (tau(beta)_x - tau(alpha)_x) + rs (tau(beta)_y - tau(alpha)_y)
        //      account for 1 factors of dSq (2 s,c factors)
        int termXp1 = (d.tauBeta.x - d.tauAlpha.x).divXpU(d.dSq); // note tauBeta.x > tauAlpha.x, so this is > 0 and rounding direction is clear
        int termXp2 = (d.tauBeta.y - d.tauAlpha.y).divXpU(d.dSq); // note this may be negative, but since tauBeta.y, tauAlpha.y >= 0, it is always in [-1, 1].
        xp = r.y.mulDownMagU(p.lambda).mulDownMagU(p.c).mulDownXpToNpU(termXp1);
        xp = xp + (termXp2 > 0 ? r.y.mulDownMagU(p.s) : r.x.mulUpMagU(p.s)).mulDownXpToNpU(termXp2);
    }

    /**
     * Maximal value for the real reserves y when the respective other balance is 0 for given invariant
     *  See calculation in Section 2.1.2. Calculation is ordered here for precision, but erorr in r is magnified by lambda
     *  Rounds down in signed direction
     */
    function maxBalances1(
        Params memory p,
        DerivedParams memory d,
        Vector2 memory r // overestimate in x-component, underestimate in y-component
    ) internal pure returns (int yp) {
        // y^+ = r lambda s (tau(beta)_x - tau(alpha)_x) + rc (tau(alpha)_y - tau(beta)_y)
        //      account for 1 factors of dSq (2 s,c factors)
        int termXp1 = (d.tauBeta.x - d.tauAlpha.x).divXpU(d.dSq); // note tauBeta.x > tauAlpha.x
        int termXp2 = (d.tauAlpha.y - d.tauBeta.y).divXpU(d.dSq);
        yp = r.y.mulDownMagU(p.lambda).mulDownMagU(p.s).mulDownXpToNpU(termXp1);
        yp = yp + (termXp2 > 0 ? r.y.mulDownMagU(p.c) : r.x.mulUpMagU(p.c)).mulDownXpToNpU(termXp2);
    }

    /**
     * @dev Compute the invariant 'r' corresponding to the given values. The invariant can't be negative, but
     *  we use a signed value to store it because all the other calculations are happening with signed ints, too.
     *  Computes r according to Prop 13 in 2.2.1 Initialization from Real Reserves
     *  orders operations to achieve best precision
     *  Returns an underestimate and a bound on error size.
     *  Enforces anti-overflow limits on balances and the computed invariant in the process.
     */
    function calculateInvariantWithError(
        uint[] memory balances,
        Params memory params,
        DerivedParams memory derived
    ) public pure returns (int, int) {
        (int x, int y) = (balances[0].toInt256(), balances[1].toInt256());
        _grequire(x.add(y) <= _MAX_BALANCES, GyroECLPPoolErrors.MAX_ASSETS_EXCEEDED);

        int AtAChi = calcAtAChi(x, y, params, derived);
        (int sqrt, int err) = calcInvariantSqrt(x, y, params, derived);
        // calculate the error in the square root term, separates cases based on sqrt >= 1/2
        // somedayTODO: can this be improved for cases of large balances (when xp error magnifies to np)
        // Note: the minimum non-zero value of sqrt is 1e-9 since the minimum argument is 1e-18
        if (sqrt > 0) {
            // err + 1 to account for O(eps_np) term ignored before
            err = (err + 1).divUpMagU(2 * sqrt);
        } else {
            // in the false case here, the extra precision error does not magnify, and so the error inside the sqrt is O(1e-18)
            // somedayTODO: The true case will almost surely never happen (can it be removed)
            err = err > 0 ? GyroPoolMath._sqrt(err.toUint256(), 5).toInt256() : int(1e9);
        }
        // calculate the error in the numerator, scale the error by 20 to be sure all possible terms accounted for
        err = ((params.lambda.mulUpMagU(x + y) / ONE_XP) + err + 1) * 20;

        // A chi \cdot A chi > 1, so round it up to round denominator up
        // denominator uses extra precision, so we do * 1/denominator so we are sure the calculation doesn't overflow
        int mulDenominator = ONE_XP.divXpU(calcAChiAChiInXp(params, derived) - ONE_XP);
        // NOTE: Anti-overflow limits on mulDenominator are checked on contract creation.

        // as alternative, could do, but could overflow: invariant = (AtAChi.add(sqrt) - err).divXp(denominator);
        int invariant = (AtAChi + sqrt - err).mulDownXpToNpU(mulDenominator);
        // error scales if denominator is small
        // NB: This error calculation computes the error in the expression "numerator / denominator", but in this code
        // we actually use the formula "numerator * (1 / denominator)" to compute the invariant. This affects this line
        // and the one below.
        err = err.mulUpXpToNpU(mulDenominator);
        // account for relative error due to error in the denominator
        // error in denominator is O(epsilon) if lambda<1e11, scale up by 10 to be sure we catch it, and add O(eps)
        // error in denominator is lambda^2 * 2e-37 and scales relative to the result / denominator
        // Scale by a constant to account for errors in the scaling factor itself and limited compounding.
        // calculating lambda^2 w/o decimals so that the calculation will never overflow, the lost precision isn't important
        err = err + ((invariant.mulUpXpToNpU(mulDenominator) * ((params.lambda * params.lambda) / 1e36)) * 40) / ONE_XP
            + 1;

        _grequire(invariant.add(err) <= _MAX_INVARIANT, GyroECLPPoolErrors.MAX_INVARIANT_EXCEEDED);

        return (invariant, err);
    }

    function calculateInvariant(
        uint[] memory balances,
        Params memory params,
        DerivedParams memory derived
    ) external pure returns (uint uinvariant) {
        (int invariant,) = calculateInvariantWithError(balances, params, derived);
        uinvariant = invariant.toUint256();
    }

    /// @dev calculate At \cdot A chi, ignores rounding direction. We will later compensate for the rounding error.
    function calcAtAChi(int x, int y, Params memory p, DerivedParams memory d) internal pure returns (int val) {
        // to save gas, pre-compute dSq^2 as it will be used 3 times
        int dSq2 = d.dSq.mulXpU(d.dSq);

        // (cx - sy) * (w/lambda + z) / lambda
        //      account for 2 factors of dSq (4 s,c factors)
        int termXp = (d.w.divDownMagU(p.lambda) + d.z).divDownMagU(p.lambda).divXpU(dSq2);
        val = (x.mulDownMagU(p.c) - y.mulDownMagU(p.s)).mulDownXpToNpU(termXp);

        // (x lambda s + y lambda c) * u, note u > 0
        int termNp = x.mulDownMagU(p.lambda).mulDownMagU(p.s) + y.mulDownMagU(p.lambda).mulDownMagU(p.c);
        val = val + termNp.mulDownXpToNpU(d.u.divXpU(dSq2));

        // (sx+cy) * v, note v > 0
        termNp = x.mulDownMagU(p.s) + y.mulDownMagU(p.c);
        val = val + termNp.mulDownXpToNpU(d.v.divXpU(dSq2));
    }

    /// @dev calculates A chi \cdot A chi in extra precision
    /// Note: this can be >1 (and involves factor of lambda^2). We can compute it in extra precision w/o overflowing b/c it will be
    /// at most 38 + 16 digits (38 from decimals, 2*8 from lambda^2 if lambda=1e8)
    /// Since we will only divide by this later, we will not need to worry about overflow in that operation if done in the right way
    /// TODO: is rounding direction ok?
    function calcAChiAChiInXp(Params memory p, DerivedParams memory d) internal pure returns (int val) {
        // to save gas, pre-compute dSq^3 as it will be used 4 times
        int dSq3 = d.dSq.mulXpU(d.dSq).mulXpU(d.dSq);

        // (A chi)_y^2 = lambda^2 u^2 + lambda 2 u v + v^2
        //      account for 3 factors of dSq (6 s,c factors)
        // SOMEDAY: In these calcs, a calculated value is multiplied by lambda and lambda^2, resp, which implies some
        // error amplification. It's fine b/c we're doing it in extra precision here, but would still be nice if it
        // could be avoided, perhaps by splitting up the numbers into a high and low part.
        val = p.lambda.mulUpMagU((2 * d.u).mulXpU(d.v).divXpU(dSq3));
        // for lambda^2 u^2 factor in rounding error in u since lambda could be big
        // Note: lambda^2 is multiplied at the end to be sure the calculation doesn't overflow, but this can lose some precision
        val = val + ((d.u + 1).mulXpU(d.u + 1).divXpU(dSq3)).mulUpMagU(p.lambda).mulUpMagU(p.lambda);
        // the next line converts from extre precision to normal precision post-computation while rounding up
        val = val + (d.v).mulXpU(d.v).divXpU(dSq3);

        // (A chi)_x^2 = (w/lambda + z)^2
        //      account for 3 factors of dSq (6 s,c factors)
        int termXp = d.w.divUpMagU(p.lambda) + d.z;
        val = val + termXp.mulXpU(termXp).divXpU(dSq3);
    }

    /// @dev calculate -(At)_x ^2 (A chi)_y ^2 + (At)_x ^2, rounding down in signed direction
    function calcMinAtxAChiySqPlusAtxSq(
        int x,
        int y,
        Params memory p,
        DerivedParams memory d
    ) internal pure returns (int val) {
        ////////////////////////////////////////////////////////////////////////////////////
        // (At)_x^2 (A chi)_y^2 = (x^2 c^2 - xy2sc + y^2 s^2) (u^2 + 2uv/lambda + v^2/lambda^2)
        //      account for 4 factors of dSq (8 s,c factors)
        //
        // (At)_x^2 = (x^2 c^2 - xy2sc + y^2 s^2)/lambda^2
        //      account for 1 factor of dSq (2 s,c factors)
        ////////////////////////////////////////////////////////////////////////////////////
        int termNp = x.mulUpMagU(x).mulUpMagU(p.c).mulUpMagU(p.c) + y.mulUpMagU(y).mulUpMagU(p.s).mulUpMagU(p.s);
        termNp = termNp - x.mulDownMagU(y).mulDownMagU(p.c * 2).mulDownMagU(p.s);

        int termXp = d.u.mulXpU(d.u) + (2 * d.u).mulXpU(d.v).divDownMagU(p.lambda)
            + d.v.mulXpU(d.v).divDownMagU(p.lambda).divDownMagU(p.lambda);
        termXp = termXp.divXpU(d.dSq.mulXpU(d.dSq).mulXpU(d.dSq).mulXpU(d.dSq));
        val = (-termNp).mulDownXpToNpU(termXp);

        // now calculate (At)_x^2 accounting for possible rounding error to round down
        // need to do 1/dSq in a way so that there is no overflow for large balances
        val = val
            + (termNp - 9).divDownMagU(p.lambda).divDownMagU(p.lambda).mulDownXpToNpU(SignedFixedPoint.ONE_XP.divXpU(d.dSq));
    }

    /// @dev calculate 2(At)_x * (At)_y * (A chi)_x * (A chi)_y, ignores rounding direction
    //  Note: this ignores rounding direction and is corrected for later
    function calc2AtxAtyAChixAChiy(
        int x,
        int y,
        Params memory p,
        DerivedParams memory d
    ) internal pure returns (int val) {
        ////////////////////////////////////////////////////////////////////////////////////
        // = ((x^2 - y^2)sc + yx(c^2-s^2)) * 2 * (zu + (wu + zv)/lambda + wv/lambda^2)
        //      account for 4 factors of dSq (8 s,c factors)
        ////////////////////////////////////////////////////////////////////////////////////
        int termNp = (x.mulDownMagU(x) - y.mulUpMagU(y)).mulDownMagU(2 * p.c).mulDownMagU(p.s);
        int xy = y.mulDownMagU(2 * x);
        termNp = termNp + xy.mulDownMagU(p.c).mulDownMagU(p.c) - xy.mulDownMagU(p.s).mulDownMagU(p.s);

        int termXp = d.z.mulXpU(d.u) + d.w.mulXpU(d.v).divDownMagU(p.lambda).divDownMagU(p.lambda);
        termXp = termXp + (d.w.mulXpU(d.u) + d.z.mulXpU(d.v)).divDownMagU(p.lambda);
        termXp = termXp.divXpU(d.dSq.mulXpU(d.dSq).mulXpU(d.dSq).mulXpU(d.dSq));

        val = termNp.mulDownXpToNpU(termXp);
    }

    /// @dev calculate -(At)_y ^2 (A chi)_x ^2 + (At)_y ^2, rounding down in signed direction
    function calcMinAtyAChixSqPlusAtySq(
        int x,
        int y,
        Params memory p,
        DerivedParams memory d
    ) internal pure returns (int val) {
        ////////////////////////////////////////////////////////////////////////////////////
        // (At)_y^2 (A chi)_x^2 = (x^2 s^2 + xy2sc + y^2 c^2) * (z^2 + 2zw/lambda + w^2/lambda^2)
        //      account for 4 factors of dSq (8 s,c factors)
        // (At)_y^2 = (x^2 s^2 + xy2sc + y^2 c^2)
        //      account for 1 factor of dSq (2 s,c factors)
        ////////////////////////////////////////////////////////////////////////////////////
        int termNp = x.mulUpMagU(x).mulUpMagU(p.s).mulUpMagU(p.s) + y.mulUpMagU(y).mulUpMagU(p.c).mulUpMagU(p.c);
        termNp = termNp + x.mulUpMagU(y).mulUpMagU(p.s * 2).mulUpMagU(p.c);

        int termXp = d.z.mulXpU(d.z) + d.w.mulXpU(d.w).divDownMagU(p.lambda).divDownMagU(p.lambda);
        termXp = termXp + (2 * d.z).mulXpU(d.w).divDownMagU(p.lambda);
        termXp = termXp.divXpU(d.dSq.mulXpU(d.dSq).mulXpU(d.dSq).mulXpU(d.dSq));
        val = (-termNp).mulDownXpToNpU(termXp);

        // now calculate (At)_y^2 accounting for possible rounding error to round down
        // need to do 1/dSq in a way so that there is no overflow for large balances
        val = val + (termNp - 9).mulDownXpToNpU(SignedFixedPoint.ONE_XP.divXpU(d.dSq));
    }

    /// @dev Rounds down. Also returns an estimate for the error of the term under the sqrt (!) and without the regular
    /// normal-precision error of O(1e-18).
    function calcInvariantSqrt(
        int x,
        int y,
        Params memory p,
        DerivedParams memory d
    ) internal pure returns (int val, int err) {
        val = calcMinAtxAChiySqPlusAtxSq(x, y, p, d) + calc2AtxAtyAChixAChiy(x, y, p, d);
        val = val + calcMinAtyAChixSqPlusAtySq(x, y, p, d);
        // error inside the square root is O((x^2 + y^2) * eps_xp) + O(eps_np), where eps_xp=1e-38, eps_np=1e-18
        // note that in terms of rounding down, error corrects for calc2AtxAtyAChixAChiy()
        // however, we also use this error to correct the invariant for an overestimate in swaps, it is all the same order though
        // Note the O(eps_np) term will be dealt with later, so not included yet
        // Note that the extra precision term doesn't propagate unless balances are > 100b
        err = (x.mulUpMagU(x) + y.mulUpMagU(y)) / 1e38;
        // we will account for the error later after the square root
        // mathematically, terms in square root > 0, so treat as 0 if it is < 0 b/c of rounding error
        val = val > 0 ? GyroPoolMath._sqrt(val.toUint256(), 5).toInt256() : int(0);
    }

    /**
     * @dev Spot price of token 0 in units of token 1.
     *  See Prop. 12 in 2.1.6 Computing Prices
     */
    function calcSpotPrice0in1(
        uint[] memory balances,
        Params memory params,
        DerivedParams memory derived,
        int invariant
    ) external pure returns (uint px) {
        // shift by virtual offsets to get v(t)
        Vector2 memory r = Vector2(invariant, invariant); // ignore r rounding for spot price, precision will be lost in TWAP anyway
        Vector2 memory ab = Vector2(virtualOffset0(params, derived, r), virtualOffset1(params, derived, r));
        Vector2 memory vec = Vector2(balances[0].toInt256() - ab.x, balances[1].toInt256() - ab.y);

        // transform to circle to get Av(t)
        vec = mulA(params, vec);
        // compute prices on circle
        Vector2 memory pc = Vector2(vec.x.divDownMagU(vec.y), ONE);

        // Convert prices back to ellipse
        // NB: These operations check for overflow because the price pc[0] might be large when vex.y is small.
        // SOMEDAY I think this probably can't actually happen due to our bounds on the different values. In this case we could do this unchecked as well.
        int pgx = scalarProd(pc, mulA(params, Vector2(ONE, 0)));
        px = pgx.divDownMag(scalarProd(pc, mulA(params, Vector2(0, ONE)))).toUint256();
    }

    /**
     * @dev Check that post-swap balances obey maximal asset bounds
     *  newBalance = post-swap balance of one asset
     *  assetIndex gives the index of the provided asset (0 = X, 1 = Y)
     */
    function checkAssetBounds(
        Params memory params,
        DerivedParams memory derived,
        Vector2 memory invariant,
        int newBal,
        uint8 assetIndex
    ) internal pure {
        if (assetIndex == 0) {
            int xPlus = maxBalances0(params, derived, invariant);
            if (!(newBal <= _MAX_BALANCES && newBal <= xPlus)) {
                _grequire(false, GyroECLPPoolErrors.ASSET_BOUNDS_EXCEEDED);
            }
            return;
        }
        {
            int yPlus = maxBalances1(params, derived, invariant);
            if (!(newBal <= _MAX_BALANCES && newBal <= yPlus)) {
                _grequire(false, GyroECLPPoolErrors.ASSET_BOUNDS_EXCEEDED);
            }
        }
    }

    function calcOutGivenIn(
        uint[] memory balances,
        uint amountIn,
        bool tokenInIsToken0,
        Params memory params,
        DerivedParams memory derived,
        Vector2 memory invariant
    ) external pure returns (uint amountOut) {
        function(int256, Params memory, DerivedParams memory, Vector2 memory) pure returns (int256) calcGiven;
        uint8 ixIn;
        uint8 ixOut;
        if (tokenInIsToken0) {
            ixIn = 0;
            ixOut = 1;
            calcGiven = calcYGivenX;
        } else {
            ixIn = 1;
            ixOut = 0;
            calcGiven = calcXGivenY;
        }

        int balInNew = balances[ixIn].add(amountIn).toInt256(); // checked because amountIn is given by the user.
        checkAssetBounds(params, derived, invariant, balInNew, ixIn);
        int balOutNew = calcGiven(balInNew, params, derived, invariant);
        // Make sub checked as an extra check against numerical error; but this really should never happen
        amountOut = balances[ixOut].sub(balOutNew.toUint256());
        // The above line guarantees that amountOut <= balances[ixOut].
    }

    function calcInGivenOut(
        uint[] memory balances,
        uint amountOut,
        bool tokenInIsToken0,
        Params memory params,
        DerivedParams memory derived,
        Vector2 memory invariant
    ) external pure returns (uint amountIn) {
        function(int256, Params memory, DerivedParams memory, Vector2 memory) pure returns (int256) calcGiven;
        uint8 ixIn;
        uint8 ixOut;
        if (tokenInIsToken0) {
            ixIn = 0;
            ixOut = 1;
            calcGiven = calcXGivenY; // this reverses compared to calcOutGivenIn
        } else {
            ixIn = 1;
            ixOut = 0;
            calcGiven = calcYGivenX; // this reverses compared to calcOutGivenIn
        }

        if (!(amountOut <= balances[ixOut])) _grequire(false, GyroECLPPoolErrors.ASSET_BOUNDS_EXCEEDED);
        int balOutNew = (balances[ixOut] - amountOut).toInt256();
        int balInNew = calcGiven(balOutNew, params, derived, invariant);
        // The checks in the following two lines should really always succeed; we keep them as extra safety against numerical error.
        checkAssetBounds(params, derived, invariant, balInNew, ixIn);
        amountIn = balInNew.toUint256().sub(balances[ixIn]);
    }

    /**
     * @dev Variables are named for calculating y given x
     *  to calculate x given y, change x->y, s->c, c->s, a_>b, b->a, tauBeta.x -> -tauAlpha.x, tauBeta.y -> tauAlpha.y
     *  calculates an overestimate of calculated reserve post-swap
     */
    function solveQuadraticSwap(
        int lambda,
        int x,
        int s,
        int c,
        Vector2 memory r, // overestimate in x component, underestimate in y
        Vector2 memory ab,
        Vector2 memory tauBeta,
        int dSq
    ) internal pure returns (int) {
        // x component will round up, y will round down, use extra precision
        Vector2 memory lamBar;
        lamBar.x = SignedFixedPoint.ONE_XP - SignedFixedPoint.ONE_XP.divDownMagU(lambda).divDownMagU(lambda);
        // Note: The following cannot become negative even with errors because we require lambda >= 1 and
        // divUpMag returns the exact result if the quotient is representable in 18 decimals.
        lamBar.y = SignedFixedPoint.ONE_XP - SignedFixedPoint.ONE_XP.divUpMagU(lambda).divUpMagU(lambda);
        // using qparams struct to avoid "stack too deep"
        QParams memory q;
        // shift by the virtual offsets
        // note that we want an overestimate of offset here so that -x'*lambar*s*c is overestimated in signed direction
        // account for 1 factor of dSq (2 s,c factors)
        int xp = x - ab.x;
        if (xp > 0) {
            q.b = (-xp).mulDownMagU(s).mulDownMagU(c).mulUpXpToNpU(lamBar.y.divXpU(dSq));
        } else {
            q.b = (-xp).mulUpMagU(s).mulUpMagU(c).mulUpXpToNpU(lamBar.x.divXpU(dSq) + 1);
        }

        // x component will round up, y will round down, use extra precision
        // account for 1 factor of dSq (2 s,c factors)
        Vector2 memory sTerm;
        // we wil take sTerm = 1 - sTerm below, using multiple lines to avoid "stack too deep"
        sTerm.x = lamBar.y.mulDownMagU(s).mulDownMagU(s).divXpU(dSq);
        sTerm.y = lamBar.x.mulUpMagU(s);
        sTerm.y = sTerm.y.mulUpMagU(s).divXpU(dSq + 1) + 1; // account for rounding error in dSq, divXp
        sTerm = Vector2(SignedFixedPoint.ONE_XP - sTerm.x, SignedFixedPoint.ONE_XP - sTerm.y);
        // ^^ NB: The components of sTerm are non-negative: We only need to worry about sTerm.y. This is non-negative b/c, because of bounds on lambda lamBar <= 1 - 1e-16, and division by dSq ensures we have enough precision so that rounding errors are never magnitude 1e-16.

        // now compute the argument of the square root
        q.c = -calcXpXpDivLambdaLambda(x, r, lambda, s, c, tauBeta, dSq);
        q.c = q.c + r.y.mulDownMagU(r.y).mulDownXpToNpU(sTerm.y);
        // the square root is always being subtracted, so round it down to overestimate the end balance
        // mathematically, terms in square root > 0, so treat as 0 if it is < 0 b/c of rounding error
        q.c = q.c > 0 ? GyroPoolMath._sqrt(q.c.toUint256(), 5).toInt256() : int(0);

        // calculate the result in q.a
        if (q.b - q.c > 0) {
            q.a = (q.b - q.c).mulUpXpToNpU(SignedFixedPoint.ONE_XP.divXpU(sTerm.y) + 1);
        } else {
            q.a = (q.b - q.c).mulUpXpToNpU(SignedFixedPoint.ONE_XP.divXpU(sTerm.x));
        }

        // lastly, add the offset, note that we want an overestimate of offset here
        return q.a + ab.y;
    }

    /**
     * @dev Calculates x'x'/λ^2 where x' = x - b = x - r (A^{-1}tau(beta))_x
     *  calculates an overestimate
     *  to calculate y'y', change x->y, s->c, c->s, tauBeta.x -> -tauAlpha.x, tauBeta.y -> tauAlpha.y
     */
    function calcXpXpDivLambdaLambda(
        int x,
        Vector2 memory r, // overestimate in x component, underestimate in y
        int lambda,
        int s,
        int c,
        Vector2 memory tauBeta,
        int dSq
    ) internal pure returns (int) {
        //////////////////////////////////////////////////////////////////////////////////
        // x'x'/lambda^2 = r^2 c^2 tau(beta)_x^2
        //      + ( r^2 2s c tau(beta)_x tau(beta)_y - rx 2c tau(beta)_x ) / lambda
        //      + ( r^2 s^2 tau(beta)_y^2 - rx 2s tau(beta)_y + x^2 ) / lambda^2
        //////////////////////////////////////////////////////////////////////////////////
        // to save gas, pre-compute dSq^2 as it will be used 3 times, and r.x^2 as it will be used 2-3 times
        // sqVars = (dSq^2, r.x^2)
        Vector2 memory sqVars = Vector2(dSq.mulXpU(dSq), r.x.mulUpMagU(r.x));

        QParams memory q; // for working terms
        // q.a = r^2 s 2c tau(beta)_x tau(beta)_y
        //      account for 2 factors of dSq (4 s,c factors)
        int termXp = tauBeta.x.mulXpU(tauBeta.y).divXpU(sqVars.x);
        if (termXp > 0) {
            q.a = sqVars.y.mulUpMagU(2 * s);
            q.a = q.a.mulUpMagU(c).mulUpXpToNpU(termXp + 7); // +7 account for rounding in termXp
        } else {
            q.a = r.y.mulDownMagU(r.y).mulDownMagU(2 * s);
            q.a = q.a.mulDownMagU(c).mulUpXpToNpU(termXp);
        }

        // -rx 2c tau(beta)_x
        //      account for 1 factor of dSq (2 s,c factors)
        if (tauBeta.x < 0) {
            // +3 account for rounding in extra precision terms
            q.b = r.x.mulUpMagU(x).mulUpMagU(2 * c).mulUpXpToNpU(-tauBeta.x.divXpU(dSq) + 3);
        } else {
            q.b = (-r.y).mulDownMagU(x).mulDownMagU(2 * c).mulUpXpToNpU(tauBeta.x.divXpU(dSq));
        }
        // q.a later needs to be divided by lambda
        q.a = q.a + q.b;

        // q.b = r^2 s^2 tau(beta)_y^2
        //      account for 2 factors of dSq (4 s,c factors)
        termXp = tauBeta.y.mulXpU(tauBeta.y).divXpU(sqVars.x) + 7; // +7 account for rounding in termXp
        q.b = sqVars.y.mulUpMagU(s);
        q.b = q.b.mulUpMagU(s).mulUpXpToNpU(termXp);

        // q.c = -rx 2s tau(beta)_y, recall that tauBeta.y > 0 so round lower in magnitude
        //      account for 1 factor of dSq (2 s,c factors)
        q.c = (-r.y).mulDownMagU(x).mulDownMagU(2 * s).mulUpXpToNpU(tauBeta.y.divXpU(dSq));

        // (q.b + q.c + x^2) / lambda
        q.b = q.b + q.c + x.mulUpMagU(x);
        q.b = q.b > 0 ? q.b.divUpMagU(lambda) : q.b.divDownMagU(lambda);

        // remaining calculation is (q.a + q.b) / lambda
        q.a = q.a + q.b;
        q.a = q.a > 0 ? q.a.divUpMagU(lambda) : q.a.divDownMagU(lambda);

        // + r^2 c^2 tau(beta)_x^2
        //      account for 2 factors of dSq (4 s,c factors)
        termXp = tauBeta.x.mulXpU(tauBeta.x).divXpU(sqVars.x) + 7; // +7 account for rounding in termXp
        int val = sqVars.y.mulUpMagU(c).mulUpMagU(c);
        return (val.mulUpXpToNpU(termXp)) + q.a;
    }

    /**
     * @dev compute y such that (x, y) satisfy the invariant at the given parameters.
     *  Note that we calculate an overestimate of y
     *   See Prop 14 in section 2.2.2 Trade Execution
     */
    function calcYGivenX(
        int x,
        Params memory params,
        DerivedParams memory d,
        Vector2 memory r // overestimate in x component, underestimate in y
    ) internal pure returns (int y) {
        // want to overestimate the virtual offsets except in a particular setting that will be corrected for later
        // note that the error correction in the invariant should more than make up for uncaught rounding directions (in 38 decimals) in virtual offsets
        Vector2 memory ab = Vector2(virtualOffset0(params, d, r), virtualOffset1(params, d, r));
        y = solveQuadraticSwap(params.lambda, x, params.s, params.c, r, ab, d.tauBeta, d.dSq);
    }

    function calcXGivenY(
        int y,
        Params memory params,
        DerivedParams memory d,
        Vector2 memory r // overestimate in x component, underestimate in y
    ) internal pure returns (int x) {
        // want to overestimate the virtual offsets except in a particular setting that will be corrected for later
        // note that the error correction in the invariant should more than make up for uncaught rounding directions (in 38 decimals) in virtual offsets
        Vector2 memory ba = Vector2(virtualOffset1(params, d, r), virtualOffset0(params, d, r));
        // change x->y, s->c, c->s, b->a, a->b, tauBeta.x -> -tauAlpha.x, tauBeta.y -> tauAlpha.y vs calcYGivenX
        x = solveQuadraticSwap(params.lambda, y, params.c, params.s, r, ba, Vector2(-d.tauAlpha.x, d.tauAlpha.y), d.dSq);
    }
}
