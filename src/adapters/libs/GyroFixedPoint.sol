// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository <https://github.com/gyrostable/concentrated-lps>.

pragma solidity ^0.8.23;

import "./balancer-labs-v2-solidity-utils/math/LogExpMath.sol";
import "./balancer-labs-v2-solidity-utils/helpers/BalancerErrors.sol";
import "./balancer-labs-v2-solidity-utils/math/BalancerMath.sol";

/* solhint-disable private-vars-leading-underscore */

// Gyroscope: Copied from Balancer's FixedPoint library. We added a few additional functions and made _require()s more
// gas-efficient.
// We renamed this to `GyroFixedPoint` to avoid name clashes with functions used in other Balancer libraries we use.

library GyroFixedPoint {
    uint internal constant ONE = 1e18; // 18 decimal places
    uint internal constant MIDDECIMAL = 1e9; // splits the fixed point decimals into two equal parts.

    uint internal constant MAX_POW_RELATIVE_ERROR = 10000; // 10^(-14)

    // Minimum base for the power function when the exponent is 'free' (larger than ONE).
    uint internal constant MIN_POW_BASE_FREE_EXPONENT = 0.7e18;

    function add(uint a, uint b) internal pure returns (uint) {
        // Fixed Point addition is the same as regular checked addition

        uint c = a + b;
        if (!(c >= a)) {
            _require(false, Errors.ADD_OVERFLOW);
        }
        return c;
    }

    function sub(uint a, uint b) internal pure returns (uint) {
        // Fixed Point addition is the same as regular checked addition

        if (!(b <= a)) {
            _require(false, Errors.SUB_OVERFLOW);
        }
        uint c = a - b;
        return c;
    }

    function mulDown(uint a, uint b) internal pure returns (uint) {
        uint product = a * b;
        if (!(a == 0 || product / a == b)) {
            _require(false, Errors.MUL_OVERFLOW);
        }

        return product / ONE;
    }

    /// @dev "U" denotes version of the math function that does not check for overflows in order to save gas
    function mulDownU(uint a, uint b) internal pure returns (uint) {
        return (a * b) / ONE;
    }

    function mulUp(uint a, uint b) internal pure returns (uint) {
        uint product = a * b;
        if (!(a == 0 || product / a == b)) {
            _require(false, Errors.MUL_OVERFLOW);
        }

        if (product == 0) {
            return 0;
        }

        // The traditional divUp formula is:
        // divUp(x, y) := (x + y - 1) / y
        // To avoid intermediate overflow in the addition, we distribute the division and get:
        // divUp(x, y) := (x - 1) / y + 1
        // Note that this requires x != 0, which we already tested for.

        return ((product - 1) / ONE) + 1;
    }

    function mulUpU(uint a, uint b) internal pure returns (uint) {
        uint product = a * b;

        if (product == 0) {
            return 0;
        }
        // The traditional divUp formula is:
        // divUp(x, y) := (x + y - 1) / y
        // To avoid intermediate overflow in the addition, we distribute the division and get:
        // divUp(x, y) := (x - 1) / y + 1
        // Note that this requires x != 0, which we already tested for.

        return ((product - 1) / ONE) + 1;
    }

    function divDown(uint a, uint b) internal pure returns (uint) {
        if (b == 0) {
            _require(false, Errors.ZERO_DIVISION);
        }

        if (a == 0) {
            return 0;
        }

        uint aInflated = a * ONE;
        if (!(aInflated / a == ONE)) {
            _require(false, Errors.DIV_INTERNAL); // mul overflow
        }

        return aInflated / b;
    }

    function divDownU(uint a, uint b) internal pure returns (uint) {
        if (b == 0) {
            _require(false, Errors.ZERO_DIVISION);
        }

        return (a * ONE) / b;
    }

    function divUp(uint a, uint b) internal pure returns (uint) {
        if (b == 0) {
            _require(false, Errors.ZERO_DIVISION);
        }

        if (a == 0) {
            return 0;
        }

        uint aInflated = a * ONE;
        if (!(aInflated / a == ONE)) {
            _require(aInflated / a == ONE, Errors.DIV_INTERNAL); // mul overflow
        }

        // The traditional divUp formula is:
        // divUp(x, y) := (x + y - 1) / y
        // To avoid intermediate overflow in the addition, we distribute the division and get:
        // divUp(x, y) := (x - 1) / y + 1
        // Note that this requires x != 0, which we already tested for.

        return ((aInflated - 1) / b) + 1;
    }

    function divUpU(uint a, uint b) internal pure returns (uint) {
        if (b == 0) {
            _require(false, Errors.ZERO_DIVISION);
        }

        if (a == 0) {
            return 0;
        }
        return ((a * ONE - 1) / b) + 1;
    }

    /**
     * @dev Like mulDown(), but it also works in some situations where mulDown(a, b) would overflow because a * b is too
     * large. We achieve this by splitting up `a` into its integer and its fractional part. `a` should be the bigger of
     * the two numbers to achieve the best overflow guarantees.
     * This won't overflow if both of
     *   - a * b ≤ 1.15e95 (raw values, i.e., a * b ≤ 1.15e59 with respect to the fixed-point values that they describe)
     *   - b ≤ 1.15e59 (raw values, i.e., a ≤ 1.15e41 with respect to the values that a describes)
     * hold. That's better than mulDown(), where we would need a * b ≤ 1.15e77 approximately.
     */
    function mulDownLargeSmall(uint a, uint b) internal pure returns (uint) {
        return add(BalancerMath.mul(a / ONE, b), mulDown(a % ONE, b));
    }

    function mulDownLargeSmallU(uint a, uint b) internal pure returns (uint) {
        return (a / ONE) * b + mulDownU(a % ONE, b);
    }

    /**
     * @dev Like divDown(), but it also works when `a` would overflow in `divDown`. This is safe if both of
     * - a ≤ 1.15e68 (raw, i.e., a ≤ 1.15e50 with respect to the value that is represented)
     * - b ≥ 1e9 (raw, i.e., b ≥ 1e-9 with respect to the value represented)
     * hold. For `divDown` it's 1.15e59 and 1.15e41, respectively.
     * Introduces some rounding error that is relevant iff b is small.
     */
    function divDownLarge(uint a, uint b) internal pure returns (uint) {
        return divDownLarge(a, b, MIDDECIMAL, MIDDECIMAL);
    }

    function divDownLargeU(uint a, uint b) internal pure returns (uint) {
        return divDownLargeU(a, b, MIDDECIMAL, MIDDECIMAL);
    }

    /**
     * @dev Like divDown(), but it also works when `a` would overflow in `divDown`. d and e must be chosen such that
     * d * e = 1e18 (raw numbers, or d * e = 1e-18 with respect to the numbers they represent in fixed point). Note that
     * this requires d, e ≤ 1e18 (raw, or d, e ≤ 1 with respect to the numbers represented).
     * This operation is safe if both of
     * - a * d ≤ 1.15e77 (raw, i.e., a * d ≤ 1.15e41 with respect to the value that is represented)
     * - b ≥ e (with respect to raw or represented numbers)
     * hold.
     * Introduces some rounding error that is relevant iff b is small and is proportional to e.
     */
    function divDownLarge(uint a, uint b, uint d, uint e) internal pure returns (uint) {
        return BalancerMath.divDown(BalancerMath.mul(a, d), BalancerMath.divUp(b, e));
    }

    /// @dev e is assumed to be non-zero, and so division by zero is not checked for it
    function divDownLargeU(uint a, uint b, uint d, uint e) internal pure returns (uint) {
        // (a * d) / (b / e)

        if (b == 0) {
            // In this case only, the denominator of the outer division is zero, and we revert
            _require(false, Errors.ZERO_DIVISION);
        }

        uint denom = 1 + (b - 1) / e;

        return (a * d) / denom;
    }

    /**
     * @dev Returns x^y, assuming both are fixed point numbers, rounding down. The result is guaranteed to not be above
     * the true value (that is, the error function expected - actual is always positive).
     */
    function powDown(uint x, uint y) internal pure returns (uint) {
        uint raw = LogExpMath.pow(x, y);
        uint maxError = add(mulUp(raw, MAX_POW_RELATIVE_ERROR), 1);

        if (raw < maxError) {
            return 0;
        }
        return sub(raw, maxError);
    }

    /**
     * @dev Returns x^y, assuming both are fixed point numbers, rounding up. The result is guaranteed to not be below
     * the true value (that is, the error function expected - actual is always negative).
     */
    function powUp(uint x, uint y) internal pure returns (uint) {
        uint raw = LogExpMath.pow(x, y);
        uint maxError = add(mulUp(raw, MAX_POW_RELATIVE_ERROR), 1);

        return add(raw, maxError);
    }

    /**
     * @dev Returns the complement of a value (1 - x), capped to 0 if x is larger than 1.
     *
     * Useful when computing the complement for values with some level of relative error, as it strips this error and
     * prevents intermediate negative values.
     */
    function complement(uint x) internal pure returns (uint) {
        return (x < ONE) ? (ONE - x) : 0;
    }
}
