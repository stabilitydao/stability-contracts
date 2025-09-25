// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

/// @notice Support 18-decimal fixed point arithmetic. All Vault calculations use this for high and uniform precision.
library FixedPoint {
    /// @notice Attempted division by zero.
    error ZeroDivision();

    // solhint-disable no-inline-assembly
    // solhint-disable private-vars-leading-underscore

    uint internal constant ONE = 1e18; // 18 decimal places
    uint internal constant TWO = 2 * ONE;
    uint internal constant FOUR = 4 * ONE;
    uint internal constant MAX_POW_RELATIVE_ERROR = 10000; // 10^(-14)

    function mulDown(uint a, uint b) internal pure returns (uint) {
        // Multiplication overflow protection is provided by Solidity 0.8.x.
        uint product = a * b;

        return product / ONE;
    }

    function divDown(uint a, uint b) internal pure returns (uint) {
        // Solidity 0.8 reverts with a Panic code (0x11) if the multiplication overflows.
        uint aInflated = a * ONE;

        // Solidity 0.8 reverts with a "Division by Zero" Panic code (0x12) if b is zero
        return aInflated / b;
    }

    /**
     * @dev Version of divUp when the input is raw (i.e., already "inflated"). For instance,
     * invariant * invariant (36 decimals) vs. invariant.mulDown(invariant) (18 decimal FP).
     * This can occur in calculations with many successive multiplications and divisions, and
     * we want to minimize the number of operations by avoiding unnecessary scaling by ONE.
     */
    function divUpRaw(uint a, uint b) internal pure returns (uint result) {
        // This check is required because Yul's `div` doesn't revert on b==0.
        if (b == 0) {
            revert ZeroDivision();
        }

        // Equivalent to:
        // result = a == 0 ? 0 : 1 + (a - 1) / b
        assembly ("memory-safe") {
            result := mul(iszero(iszero(a)), add(1, div(sub(a, 1), b)))
        }
    }
}
