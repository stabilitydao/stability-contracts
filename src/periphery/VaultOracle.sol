// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IAggregatorInterfaceMinimal} from "../integrations/chainlink/IAggregatorInterfaceMinimal.sol";
import {IVault} from "../interfaces/IVault.sol";

/// @title Minimal Chainlink-compatible vault trusted price feed
/// @author Alien Deployer (https://github.com/a17)
contract VaultOracle is IAggregatorInterfaceMinimal {
    address public immutable vault;

    constructor(address vault_) {
        // slither-disable-next-line missing-zero-check
        vault = vault_;
        // slither-disable-next-line unused-return
        (, bool trusted) = IVault(vault_).price();
        require(trusted, "Not trusted");
    }

    /// @inheritdoc IAggregatorInterfaceMinimal
    function latestAnswer() external view returns (int) {
        // slither-disable-next-line unused-return
        (uint price,) = IVault(vault).price();
        return int(price / 10 ** 10);
    }
}
