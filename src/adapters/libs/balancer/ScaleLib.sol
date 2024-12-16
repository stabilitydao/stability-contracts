// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./FixedPoint.sol";

/// @dev Library for up scaling / downscaling amounts for tokens with different decimals
/// @dev Used for Balancer swappers
/// @dev taken from https://github.com/balancer-labs/balancer-v2-monorepo/blob/c18ff2686c61a8cbad72cdcfc65e9b11476fdbc3/pkg/pool-utils/contracts/BasePool.sol#L520
library ScaleLib {
    function _upscale(uint amount, uint scalingFactor) internal pure returns (uint) {
        return FixedPoint.mulDown(amount, scalingFactor);
    }

    function _upscaleArray(uint[] memory amounts, uint[] memory scalingFactors) internal pure {
        uint len = amounts.length;
        for (uint i = 0; i < len; ++i) {
            amounts[i] = FixedPoint.mulDown(amounts[i], scalingFactors[i]);
        }
    }

    function _downscaleDown(uint amount, uint scalingFactor) internal pure returns (uint) {
        return FixedPoint.divDown(amount, scalingFactor);
    }
}
