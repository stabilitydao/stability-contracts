// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

interface IPPYLpOracle {
    event SetBlockCycleNumerator(uint16 newBlockCycleNumerator);

    function getPtToAssetRate(address market, uint32 duration) external view returns (uint);

    function getYtToAssetRate(address market, uint32 duration) external view returns (uint);

    function getLpToAssetRate(address market, uint32 duration) external view returns (uint);

    function getPtToSyRate(address market, uint32 duration) external view returns (uint);

    function getYtToSyRate(address market, uint32 duration) external view returns (uint);

    function getLpToSyRate(address market, uint32 duration) external view returns (uint);

    function getOracleState(
        address market,
        uint32 duration
    )
        external
        view
        returns (bool increaseCardinalityRequired, uint16 cardinalityRequired, bool oldestObservationSatisfied);

    function blockCycleNumerator() external view returns (uint16);
}
