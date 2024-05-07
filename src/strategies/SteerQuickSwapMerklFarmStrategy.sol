// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { ERC165CheckerUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { ISteerPeriphery } from "./interfaces/ISteerPeriphery.sol";
import { IGasVault } from "./interfaces/IGasVault.sol";
import { IStrategyRegistry } from "./interfaces/IStrategyRegistry.sol";
import { IVaultRegistry } from "./interfaces/IVaultRegistry.sol";
import { IStakingRewards } from "./interfaces/IStakingRewards.sol";
import { IMultiPositionManager } from "./interfaces/IMultiPositionManager.sol";
import { IBaseDeposit } from "./interfaces/IBaseDeposit.sol";
import { IDynamicJobs } from "./interfaces/IDynamicJobs.sol";

/// @title Periphery contract to facilitate common actions on the protocol
/// @author Steer Protocol
/// @dev You can use this contract to enumerate strategy and vault details but also create, join, and leave vaults
/// @dev This contract is not intended to hold any tokens in between two or more transactions, it only hold tokens transiently within a single transaction and transfers the tokens in the same transaction.
/// @dev This function should be used when doing protocol integrations
contract SteerPeriphery is
    ISteerPeriphery,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using ERC165CheckerUpgradeable for address;
    using SafeERC20 for IERC20;
    // Storage

    address internal strategyRegistry;
    address internal vaultRegistry;
    address internal stakingRewards;
    address internal gasVault;

    /// @notice The IPFS reference of the node configuration.
    string public nodeConfig;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer() {}

    // External Functions

    function initialize(
        address _strategyRegistry,
        address _vaultRegistry,
        address _gasVault,
        address _stakingRewards,
        string calldata _nodeConfig
    ) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        strategyRegistry = _strategyRegistry;
        vaultRegistry = _vaultRegistry;
        gasVault = _gasVault;
        stakingRewards = _stakingRewards;
        nodeConfig = _nodeConfig;
    }

    ///@dev Only for owner
    ///@dev Sets the config for node
    function setNodeConfig(string memory _nodeConfig) external onlyOwner {
        nodeConfig = _nodeConfig;
    }

    /// @dev Deposits tokens in proportion to the vault's current holdings.
    /// @dev These tokens sit in the vault and are not used for liquidity on
    ///      Uniswap until the next rebalance.
    /// @param vaultAddress The address of the vault to deposit to
    /// @param amount0Desired Max amount of token0 to deposit
    /// @param amount1Desired Max amount of token1 to deposit
    /// @param amount0Min Revert if resulting `amount0` is less than this
    /// @param amount1Min Revert if resulting `amount1` is less than this
    /// @param to Recipient of shares
    function deposit(
        address vaultAddress,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external {
        _deposit(
            vaultAddress,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min,
            to
        );
    }

    /// @dev Deposits tokens in proportion to the vault's current holdings and stake the share.
    /// @dev These tokens sit in the vault and are not used for liquidity on
    ///      Uniswap until the next rebalance.
    /// @param vaultAddress The address of the vault to deposit to
    /// @param amount0Desired Max amount of token0 to deposit
    /// @param amount1Desired Max amount of token1 to deposit
    /// @param amount0Min Revert if resulting `amount0` is less than this
    /// @param amount1Min Revert if resulting `amount1` is less than this
    /// @param poolId The id of the pool in which the share should be staked
    function depositAndStake(
        address vaultAddress,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 poolId
    ) external {
        require(
            vaultAddress != address(0) &&
                IStakingRewards(stakingRewards).getPool(poolId).stakingToken ==
                vaultAddress,
            "Incorrect pool id"
        );

        uint256 share = _deposit(
            vaultAddress,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min,
            address(this)
        );

        IERC20(vaultAddress).approve(stakingRewards, share);
        IStakingRewards(stakingRewards).stakeFor(msg.sender, share, poolId);
    }

    function vaultDetailsByAddress(
        address vault
    )
        external
        view
        returns (IMultiPositionManager.VaultDetails memory details)
    {
        IMultiPositionManager vaultInstance = IMultiPositionManager(vault);

        IERC20Metadata token0 = IERC20Metadata(vaultInstance.token0());
        IERC20Metadata token1 = IERC20Metadata(vaultInstance.token1());

        // Get total amounts, excluding fees
        (uint256 bal0, uint256 bal1) = vaultInstance.getTotalAmounts();

        return
            IMultiPositionManager.VaultDetails(
                IVaultRegistry(vaultRegistry).beaconTypes(vault),
                vaultInstance.token0(),
                vaultInstance.token1(),
                IERC20Metadata(vault).name(),
                IERC20Metadata(vault).symbol(),
                IERC20Metadata(vault).decimals(),
                token0.name(),
                token1.name(),
                token0.symbol(),
                token1.symbol(),
                token0.decimals(),
                token1.decimals(),
                IUniswapV3Pool(vaultInstance.pool()).fee(),
                vaultInstance.totalSupply(),
                bal0,
                bal1,
                vault
            );
    }

    function algebraVaultDetailsByAddress(
        address vault
    )
        external
        view
        returns (IMultiPositionManager.AlgebraVaultDetails memory details)
    {
        IMultiPositionManager vaultInstance = IMultiPositionManager(vault);

        IERC20Metadata token0 = IERC20Metadata(vaultInstance.token0());
        IERC20Metadata token1 = IERC20Metadata(vaultInstance.token1());

        // Get total amounts, excluding fees
        (uint256 bal0, uint256 bal1) = vaultInstance.getTotalAmounts();

        return
            IMultiPositionManager.AlgebraVaultDetails(
                IVaultRegistry(vaultRegistry).beaconTypes(vault),
                vaultInstance.token0(),
                vaultInstance.token1(),
                IERC20Metadata(vault).name(),
                IERC20Metadata(vault).symbol(),
                IERC20Metadata(vault).decimals(),
                token0.name(),
                token1.name(),
                token0.symbol(),
                token1.symbol(),
                token0.decimals(),
                token1.decimals(),
                vaultInstance.totalSupply(),
                bal0,
                bal1,
                vault
            );
    }

    function vaultBalancesByAddressWithFees(
        address vault
    ) external returns (IMultiPositionManager.VaultBalance memory balances) {
        IMultiPositionManager vaultInstance = IMultiPositionManager(vault);
        vaultInstance.poke();
        (uint256 bal0, uint256 bal1) = vaultInstance.getTotalAmounts();

        return IMultiPositionManager.VaultBalance(bal0, bal1);
    }

    function createVaultAndStrategy(
        CVSParams calldata cvsParams
    ) external payable returns (uint256 tokenId, address newVault) {
        tokenId = IStrategyRegistry(strategyRegistry).createStrategy(
            cvsParams.strategyCreator,
            cvsParams.name,
            cvsParams.execBundle,
            cvsParams.maxGasCost,
            cvsParams.maxGasPerAction
        );
        newVault = IVaultRegistry(vaultRegistry).createVault(
            cvsParams.params,
            tokenId,
            cvsParams.beaconName,
            cvsParams.vaultManager,
            cvsParams.payloadIpfs
        );
        // Deposit gas
        IGasVault(gasVault).deposit{ value: msg.value }(newVault);
    }

    function createVaultAndDepositGas(
        CVDGParams calldata cvdgParams
    ) external payable returns (address newVault) {
        newVault = IVaultRegistry(vaultRegistry).createVault(
            cvdgParams.params,
            cvdgParams.tokenId,
            cvdgParams.beaconName,
            cvdgParams.vaultManager,
            cvdgParams.payloadIpfs
        );
        // Deposit gas
        IGasVault(gasVault).deposit{ value: msg.value }(newVault);
    }

    function createVaultStrategyAndRegisterJob(
        CVSRJParams calldata cvsrjParams
    ) external payable returns (uint256 tokenId, address newVault) {
        tokenId = IStrategyRegistry(strategyRegistry).createStrategy(
            cvsrjParams.strategyCreator,
            cvsrjParams.name,
            cvsrjParams.execBundle,
            cvsrjParams.maxGasCost,
            cvsrjParams.maxGasPerAction
        );
        newVault = IVaultRegistry(vaultRegistry).createVault(
            cvsrjParams.jobInitParams,
            tokenId,
            cvsrjParams.beaconName,
            cvsrjParams.vaultManager,
            cvsrjParams.payloadIpfs
        );
        // Deposit gas
        IGasVault(gasVault).deposit{ value: msg.value }(newVault);

        //Regitser Job
        IDynamicJobs(newVault).registerJob(
            cvsrjParams.userProvidedData,
            cvsrjParams.targetAddresses,
            cvsrjParams.jobName,
            cvsrjParams.ipfsForJobDetails
        );
    }

    // Public Functions

    /// @dev Get the strategies by creator
    /// @param creator The creator of the strategies
    /// @return The List of strategies created by the creator
    function strategiesByCreator(
        address creator
    ) public view returns (IStrategyRegistry.RegisteredStrategy[] memory) {
        // Find the userse balance
        uint256 strategyBalance = IStrategyRegistry(strategyRegistry)
            .balanceOf(creator);

        // Create an array to hold the strategy details
        // which is the same length of the balance of the registered strategies
        IStrategyRegistry.RegisteredStrategy[]
            memory userStrategies = new IStrategyRegistry.RegisteredStrategy[](
                strategyBalance
            );

        uint256 tokenId;
        // Iterate through the user's strategies and fill the array
        for (uint256 i; i != strategyBalance; ++i) {
            // Get token id of a strategy based on the owner and the index of the strategy
            tokenId = IStrategyRegistry(strategyRegistry).tokenOfOwnerByIndex(
                creator,
                i
            );

            // Using the tokenId, get the strategy details from the strategy registry
            IStrategyRegistry.RegisteredStrategy
                memory strategy = IStrategyRegistry(strategyRegistry)
                    .getRegisteredStrategy(tokenId);

            // Add the strategy to the array based on the loop index
            userStrategies[i] = strategy;
        }

        // Return the array of strategies
        return userStrategies;
    }

    /// @dev Get the vaults using a given strategy
    /// @param strategyId The strategyId (ERC-721 tokenId)
    /// @return The List of vault details using the strategy
    function vaultsByStrategy(
        uint256 strategyId
    ) public view returns (IVaultRegistry.VaultData[] memory) {
        // Get the amount of vaults using the strategy
        uint256 vaultCount = IVaultRegistry(vaultRegistry)
            .getVaultCountByStrategyId(strategyId);

        // Create an array to hold the vault details
        IVaultRegistry.VaultData[]
            memory strategyVaults = new IVaultRegistry.VaultData[](vaultCount);

        IVaultRegistry.VaultData memory thisData;
        // Iterate through the vaults and fill the array
        for (uint256 i; i != vaultCount; ++i) {
            // Retrieve the VaultData struct using the
            // strategyId and the index of the vault for the strategy
            thisData = IVaultRegistry(vaultRegistry)
                .getVaultByStrategyAndIndex(strategyId, i);

            // Add the vault to the array based on the loop index
            strategyVaults[i] = thisData;
        }

        // Return the array of vaultData
        return strategyVaults;
    }

    // Internal Functions

    /// @dev Deposits tokens in proportion to the vault's current holdings.
    /// @dev These tokens sit in the vault and are not used for liquidity on
    ///      Uniswap until the next rebalance.
    /// @param vaultAddress The address of the vault to deposit to
    /// @param amount0Desired Max amount of token0 to deposit
    /// @param amount1Desired Max amount of token1 to deposit
    /// @param amount0Min Revert if resulting `amount0` is less than this
    /// @param amount1Min Revert if resulting `amount1` is less than this
    /// @param to Recipient of shares
    /// @return shares Number of shares minted
    function _deposit(
        address vaultAddress,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) internal returns (uint256) {
        require(
            keccak256(
                abi.encodePacked(
                    IVaultRegistry(vaultRegistry).beaconTypes(vaultAddress)
                )
            ) != keccak256(abi.encodePacked("")),
            "Invalid Vault"
        );
        IMultiPositionManager vaultInstance = IMultiPositionManager(
            vaultAddress
        );
        IERC20 token0 = IERC20(vaultInstance.token0());
        IERC20 token1 = IERC20(vaultInstance.token1());
        if (amount0Desired > 0)
            token0.safeTransferFrom(msg.sender, address(this), amount0Desired);
        if (amount1Desired > 0)
            token1.safeTransferFrom(msg.sender, address(this), amount1Desired);
        token0.approve(vaultAddress, amount0Desired);
        token1.approve(vaultAddress, amount1Desired);

        (uint256 share, uint256 amount0, uint256 amount1) = vaultInstance
            .deposit(
                amount0Desired,
                amount1Desired,
                amount0Min,
                amount1Min,
                to
            );

        if (amount0Desired > amount0) {
            token0.approve(vaultAddress, 0);
            token0.safeTransfer(msg.sender, amount0Desired - amount0);
        }
        if (amount1Desired > amount1) {
            token1.approve(vaultAddress, 0);
            token1.safeTransfer(msg.sender, amount1Desired - amount1);
        }

        return share;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}