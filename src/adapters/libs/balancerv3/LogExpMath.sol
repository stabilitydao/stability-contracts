// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// solhint-disable

/**
 * @dev Exponentiation and logarithm functions for 18 decimal fixed point numbers (both base and exponent/argument).
 *
 * Exponentiation and logarithm with arbitrary bases (x^y and log_x(y)) are implemented by conversion to natural
 * exponentiation and logarithm (where the base is Euler's number).
 *
 * All math operations are unchecked in order to save gas.
 *
 * @author Fernando Martinelli - @fernandomartinelli
 * @author Sergio Yuhjtman     - @sergioyuhjtman
 * @author Daniel Fernandez    - @dmf7z
 */
library LogExpMath {
    /// @notice This error is thrown when a base is not within an acceptable range.
    error BaseOutOfBounds();

    /// @notice This error is thrown when a exponent is not within an acceptable range.
    error ExponentOutOfBounds();

    /// @notice This error is thrown when the exponent * ln(base) is not within an acceptable range.
    error ProductOutOfBounds();

    /// @notice This error is thrown when an exponent used in the exp function is not within an acceptable range.
    error InvalidExponent();

    /// @notice This error is thrown when a variable or result is not within the acceptable bounds defined in the function.
    error OutOfBounds();

    // All fixed point multiplications and divisions are inlined. This means we need to divide by ONE when multiplying
    // two numbers, and multiply by ONE when dividing them.

    // All arguments and return values are 18 decimal fixed point numbers.
    int constant ONE_18 = 1e18;

    // Internally, intermediate values are computed with higher precision as 20 decimal fixed point numbers, and in the
    // case of ln36, 36 decimals.
    int constant ONE_20 = 1e20;
    int constant ONE_36 = 1e36;

    // The domain of natural exponentiation is bound by the word size and number of decimals used.
    //
    // Because internally the result will be stored using 20 decimals, the largest possible result is
    // (2^255 - 1) / 10^20, which makes the largest exponent ln((2^255 - 1) / 10^20) = 130.700829182905140221.
    // The smallest possible result is 10^(-18), which makes largest negative argument
    // ln(10^(-18)) = -41.446531673892822312.
    // We use 130.0 and -41.0 to have some safety margin.
    int constant MAX_NATURAL_EXPONENT = 130e18;
    int constant MIN_NATURAL_EXPONENT = -41e18;

    // Bounds for ln_36's argument. Both ln(0.9) and ln(1.1) can be represented with 36 decimal places in a fixed point
    // 256 bit integer.
    int constant LN_36_LOWER_BOUND = ONE_18 - 1e17;
    int constant LN_36_UPPER_BOUND = ONE_18 + 1e17;

    uint constant MILD_EXPONENT_BOUND = 2 ** 254 / uint(ONE_20);

    /// forge-lint: disable-start(screaming-snake-case-const)
    // 18 decimal constants
    int constant x0 = 128000000000000000000; // 2ˆ7
    int constant a0 = 38877084059945950922200000000000000000000000000000000000; // eˆ(x0) (no decimals)
    int constant x1 = 64000000000000000000; // 2ˆ6
    int constant a1 = 6235149080811616882910000000; // eˆ(x1) (no decimals)

    // 20 decimal constants
    int constant x2 = 3200000000000000000000; // 2ˆ5
    int constant a2 = 7896296018268069516100000000000000; // eˆ(x2)
    int constant x3 = 1600000000000000000000; // 2ˆ4
    int constant a3 = 888611052050787263676000000; // eˆ(x3)
    int constant x4 = 800000000000000000000; // 2ˆ3
    int constant a4 = 298095798704172827474000; // eˆ(x4)
    int constant x5 = 400000000000000000000; // 2ˆ2
    int constant a5 = 5459815003314423907810; // eˆ(x5)
    int constant x6 = 200000000000000000000; // 2ˆ1
    int constant a6 = 738905609893065022723; // eˆ(x6)
    int constant x7 = 100000000000000000000; // 2ˆ0
    int constant a7 = 271828182845904523536; // eˆ(x7)
    int constant x8 = 50000000000000000000; // 2ˆ-1
    int constant a8 = 164872127070012814685; // eˆ(x8)
    int constant x9 = 25000000000000000000; // 2ˆ-2
    int constant a9 = 128402541668774148407; // eˆ(x9)
    int constant x10 = 12500000000000000000; // 2ˆ-3
    int constant a10 = 113314845306682631683; // eˆ(x10)
    int constant x11 = 6250000000000000000; // 2ˆ-4
    int constant a11 = 106449445891785942956; // eˆ(x11)
    /// forge-lint: disable-end(screaming-snake-case-const)

}
