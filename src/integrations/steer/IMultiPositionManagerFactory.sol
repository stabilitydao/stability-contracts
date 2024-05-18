// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IMultiPositionManagerFactory {

    function getHeartBeat(address _base, address _quote) external view returns (uint);

    function chainlinkRegistry() external view returns (address);

    function governance() external view returns (address);

    function setMinHeartbeat(address _base, address _quote, uint _period) external;
}
