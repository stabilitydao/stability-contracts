// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
pragma experimental ABIEncoderV2;

import "../adapters/libs/GyroECLPMath.sol";

/// @title Interface for GyroECLP pools
/// @author Jude (https://github.com/iammrjude)
interface IGyroECLPPool {
    function getECLPParams()
        external
        view
        returns (GyroECLPMath.Params memory params, GyroECLPMath.DerivedParams memory d);
    function getInvariant() external view returns (uint);
    function getPrice() external view returns (uint spotPrice);
}
