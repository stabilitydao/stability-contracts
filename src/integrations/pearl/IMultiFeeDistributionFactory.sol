// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IMultiFeeDistributionFactory {
    function vaultToStaker(address ichiVault) external view returns (address staker);
}
