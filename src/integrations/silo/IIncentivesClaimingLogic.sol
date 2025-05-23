// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IIncentivesClaimingLogic {
  error SiloIncentivesControllerZeroAddress();
  error VaultIncentivesControllerZeroAddress();

  function SILO_INCENTIVES_CONTROLLER() external view returns (address);

  function VAULT_INCENTIVES_CONTROLLER() external view returns (address);

  function claimRewardsAndDistribute() external;
}