// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;
import "./IVaultRegistry.sol";
import "./IStrategyRegistry.sol";
import "./IMultiPositionManager.sol";

interface ISteerPeriphery {
    struct CVSParams {
        address strategyCreator;
        string name;
        string execBundle;
        uint128 maxGasCost;
        uint128 maxGasPerAction;
        bytes params;
        string beaconName;
        address vaultManager;
        string payloadIpfs;
    }

    struct CVDGParams {
        uint256 tokenId;
        bytes params;
        string beaconName;
        address vaultManager;
        string payloadIpfs;
    }

    struct CVSRJParams {
        address strategyCreator;
        string name;
        string execBundle;
        uint128 maxGasCost;
        uint128 maxGasPerAction;
        bytes jobInitParams;
        string beaconName;
        address vaultManager;
        string payloadIpfs;
        bytes[] userProvidedData;
        address[] targetAddresses;
        string jobName;
        string ipfsForJobDetails;
    }

    function vaultsByStrategy(
        uint256 _strategyId
    ) external view returns (IVaultRegistry.VaultData[] memory);

    function strategiesByCreator(
        address _address
    ) external view returns (IStrategyRegistry.RegisteredStrategy[] memory);

    function deposit(
        address _vaultAddress,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external;

    function vaultDetailsByAddress(
        address _vault
    )
        external
        view
        returns (IMultiPositionManager.VaultDetails memory details);

    function vaultBalancesByAddressWithFees(
        address _vault
    ) external returns (IMultiPositionManager.VaultBalance memory balances);

    function createVaultAndStrategy(
        CVSParams calldata cvsParams
    ) external payable returns (uint256 tokenId, address newVault);

    function createVaultAndDepositGas(
        CVDGParams calldata cvdgParams
    ) external payable returns (address newVault);

    function createVaultStrategyAndRegisterJob(
        CVSRJParams calldata cvsrjParams
    ) external payable returns (uint256 tokenId, address newVault);
}