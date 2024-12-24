// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library LegacyOZMath {
    function mul(uint a, uint b) internal pure returns (uint) {
        return a * b;
    }

    function div(uint a, uint b, bool roundUp) internal pure returns (uint) {
        return roundUp ? divUp(a, b) : divDown(a, b);
    }

    function divUp(uint a, uint b) internal pure returns (uint) {
        if (a == 0) {
            return 0;
        } else {
            return 1 + (a - 1) / b;
        }
    }

    function divDown(uint a, uint b) internal pure returns (uint) {
        return a / b;
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint a, uint b) internal pure returns (uint) {
        return a > b ? a : b;
    }
}
