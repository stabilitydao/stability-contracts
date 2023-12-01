// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IOpsProxyFactory {
    /**
     * @return address Proxy address owned by account.
     * @return bool Whether if proxy is deployed
     */
    function getProxyOf(address account) external view returns (address, bool);
}
