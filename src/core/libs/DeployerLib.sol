// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../proxy/VaultProxy.sol";
import "../proxy/StrategyProxy.sol";

library DeployerLib {
    function deployVaultProxy() external returns (address) {
        return address(new VaultProxy());
    }

    function deployStrategyProxy() external returns (address) {
        return address(new StrategyProxy());
    }
}
