// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library ALMPositionNameLib {
    // Fill-Up, Classic, etc
    uint internal constant NARROW = 0;
    // Fill-Up, Classic, etc
    uint internal constant WIDE = 1;
    // Gamma Pegged
    uint internal constant PEGGED = 2;
    // Stablecoin presets
    uint internal constant STABLE = 3;
    // Steer Moving Volatility Channel Strategy - Medium
    uint internal constant NARROW_VOLATILITY_CHANNEL = 4;
    // Steer Elastic Expansion Strategy
    uint internal constant NARROW_ELASTIC = 5;

    // todo move this method to factory libs and use externally, not need to deploy it for each strategy
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
        if (preset == NARROW_VOLATILITY_CHANNEL) {
            return "Narrow Volatility Channel";
        }
        if (preset == NARROW_ELASTIC) {
            return "Narrow Elastic Expansion";
        }

        return "";
    }
}
