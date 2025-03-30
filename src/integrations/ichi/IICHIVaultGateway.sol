// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IICHIVaultGateway {
    function forwardDepositToICHIVault(address vault, address vaultDeployer, address token, uint256 amount, uint256 minimumProceeds, address to) external;
    function forwardWithdrawFromICHIVault(address vault, address vaultDeployer, uint256 shares, address to, uint256 minAmount0, uint256 minAmount1) external;
}