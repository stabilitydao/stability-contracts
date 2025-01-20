// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IAggregatorInterfaceMinimal} from "../integrations/chainlink/IAggregatorInterfaceMinimal.sol";
import {IVault} from "../interfaces/IVault.sol";

/// @title Minimal Chainlink-compatible vault trusted price feed
/// @author Alien Deployer (https://github.com/a17)
contract VaultOracle is IAggregatorInterfaceMinimal {
    address public immutable vault;

    constructor(address vault_) {
        vault = vault_;
        (, bool trusted) = IVault(vault_).price();
        require(trusted, "Not trusted");
    }

    /// @inheritdoc IAggregatorInterfaceMinimal
    function latestAnswer() external view returns (int) {
        (uint price,) = IVault(vault).price();
        return int(price / 10 ** 10);
    }
}
