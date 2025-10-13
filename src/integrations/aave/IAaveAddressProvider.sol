// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice AAVE address provider for AAVE 3.0.2
interface IAaveAddressProvider {

    function getACLAdmin() external view returns (address);

    function getACLManager() external view returns (address);

    function getAddress(bytes32 id) external view returns (address);

    function getMarketId() external view returns (string memory);

    function getPool() external view returns (address);

    function getPoolConfigurator() external view returns (address);

    function getPoolDataProvider() external view returns (address);

    function getPriceOracle() external view returns (address);

    function getPriceOracleSentinel() external view returns (address);

    function owner() external view returns (address);

    function renounceOwnership() external;

    function setACLAdmin(address newAclAdmin) external;

    function setACLManager(address newAclManager) external;

    function setAddress(bytes32 id, address newAddress) external;

    function setAddressAsProxy(bytes32 id, address newImplementationAddress) external;

    function setMarketId(string memory newMarketId) external;

    function setPoolConfiguratorImpl(address newPoolConfiguratorImpl) external;

    function setPoolDataProvider(address newDataProvider) external;

    function setPoolImpl(address newPoolImpl) external;

    function setPriceOracle(address newPriceOracle) external;

    function setPriceOracleSentinel(address newPriceOracleSentinel) external;

    function transferOwnership(address newOwner) external;
}
