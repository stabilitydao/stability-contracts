// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {VaultProxy} from "../proxy/VaultProxy.sol";
import {StrategyProxy} from "../proxy/StrategyProxy.sol";

library DeployerLib {
    function deployVaultProxy() external returns (address) {
        return address(new VaultProxy());
    }

    function deployStrategyProxy() external returns (address) {
        return address(new StrategyProxy());
    }
}
