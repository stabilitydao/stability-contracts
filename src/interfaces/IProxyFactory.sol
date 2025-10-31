// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IProxyFactory {
    /// @dev Initialize proxy factory
    /// @param platform_ Platform of the stability
    function initialize(address platform_) external;

    /// @dev Deploy and initialize new Proxy contract
    /// @param salt Salt for Create2
    /// @param implementation Contract logic for proxy to be initialized
    /// @return proxy Deployed address
    function deployProxy(bytes32 salt, address implementation) external returns (address proxy);

    /// @notice Get init code hash for Create2 addresses generation
    /// @return Keccak256 hash of encoded Proxy creation code
    function getProxyInitCodeHash() external pure returns (bytes32);

    /// @notice Check proxy address that will be deployed
    /// @param salt Salt for Create2
    /// @return Deployed address
    function getCreate2Address(bytes32 salt) external view returns (address);
}
