// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library ALMPositionNameLib {
    uint internal constant NARROW = 0;
    uint internal constant WIDE = 1;
    uint internal constant PEGGED = 2;
    uint internal constant STABLE = 3;

    function getName(uint preset) internal pure returns (string memory) {
        if (preset == NARROW) {
            return "Narrow";
        }
        if (preset == WIDE) {
            return "Wide";
        }
        if (preset == PEGGED) {
            return "Pegged";
        }
        if (preset == STABLE) {
            return "Stable";
        }

        return "";
    }
}
