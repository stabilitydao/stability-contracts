// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @notice Creating vaults, upgrading vaults and strategies, vault list, farms and strategy logics management
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
/// @author HCrypto7 (https://github.com/hcrypto7)
interface IFactory {
    //region ----- Custom Errors -----

    error VaultImplementationIsNotAvailable();
    error StrategyImplementationIsNotAvailable();
    error YouDontHaveEnoughTokens(uint userBalance, uint requireBalance, address payToken);
    error SuchVaultAlreadyDeployed(bytes32 key);
    error NotActiveVault();
    error UpgradeDenied(bytes32 _hash);
    error AlreadyLastVersion(bytes32 _hash);
    error NotStrategy();

    //endregion ----- Custom Errors -----

    //region ----- Events -----

    event VaultAndStrategy(
        address indexed deployer,
        string vaultType,
        string strategyId,
        address vault,
        address strategy,
        string name,
        string symbol,
        address[] assets,
        bytes32 deploymentKey,
        uint vaultManagerTokenId
    );
    event StrategyProxyUpgraded(address proxy, address oldImplementation, address newImplementation);
    event VaultProxyUpgraded(address proxy, address oldImplementation, address newImplementation);
    event VaultConfigChanged(
        string type_, address implementation, bool deployAllowed, bool upgradeAllowed, bool newVaultType
    );
    event StrategyLogicConfigChanged(
        string id, address implementation, bool deployAllowed, bool upgradeAllowed, bool newStrategy
    );
    event VaultStatus(address indexed vault, uint newStatus);
    event NewFarm(Farm[] farms);
    event UpdateFarm(uint id, Farm farm);
    event SetStrategyAvailableInitParams(string id, address[] initAddresses, uint[] initNums, int24[] initTicks);
    event AliasNameChanged(address indexed operator, address indexed tokenAddress, string newAliasName);

    //endregion -- Events -----

    //region ----- Data types -----

    /// @custom:storage-location erc7201:stability.Factory
    struct FactoryStorage {
        /// @inheritdoc IFactory
        mapping(bytes32 typeHash => VaultConfig) vaultConfig;
        /// @inheritdoc IFactory
        mapping(bytes32 idHash => StrategyLogicConfig) strategyLogicConfig;
        /// @inheritdoc IFactory
        mapping(bytes32 deploymentKey => address vaultProxy) deploymentKey;
        /// @inheritdoc IFactory
        mapping(address vault => uint status) vaultStatus;
        /// @inheritdoc IFactory
        mapping(address address_ => bool isStrategy_) isStrategy;
        EnumerableSet.Bytes32Set vaultTypeHashes;
        EnumerableSet.Bytes32Set strategyLogicIdHashes;
        mapping(uint => mapping(uint => uint)) __deprecated1;
        address[] deployedVaults;
        Farm[] farms;
        /// @inheritdoc IFactory
        mapping(bytes32 idHash => StrategyAvailableInitParams) strategyAvailableInitParams;
        mapping(address tokenAddress => string aliasName) aliasNames;
    }

    struct VaultConfig {
        string vaultType;
        address implementation;
        bool deployAllowed;
        bool upgradeAllowed;
        uint buildingPrice;
    }

    struct StrategyLogicConfig {
        string id;
        address implementation;
        bool deployAllowed;
        bool upgradeAllowed;
        bool farming;
        uint tokenId;
    }

    struct Farm {
        uint status;
        address pool;
        string strategyLogicId;
        address[] rewardAssets;
        address[] addresses;
        uint[] nums;
        int24[] ticks;
    }

    struct StrategyAvailableInitParams {
        address[] initAddresses;
        uint[] initNums;
        int24[] initTicks;
    }

    //endregion -- Data types -----

    //region ----- View functions -----

    /// @notice All vaults deployed by the factory
    /// @return Vault proxy addresses
    function deployedVaults() external view returns (address[] memory);

    /// @notice Total vaults deployed
    function deployedVaultsLength() external view returns (uint);

    /// @notice Get vault by VaultManager tokenId
    /// @param id Vault array index. Same as tokenId of VaultManager NFT
    /// @return Address of VaultProxy
    function deployedVault(uint id) external view returns (address);

    /// @notice All farms known by the factory in current network
    function farms() external view returns (Farm[] memory);

    /// @notice Total farms known by the factory in current network
    function farmsLength() external view returns (uint);

    /// @notice Farm data by farm index
    /// @param id Index of farm
    function farm(uint id) external view returns (Farm memory);

    /// @notice Strategy logic settings
    /// @param idHash keccak256 hash of strategy logic string ID
    /// @return config Strategy logic settings
    function strategyLogicConfig(bytes32 idHash) external view returns (StrategyLogicConfig memory config);

    /// @notice All known strategies
    /// @return Array of keccak256 hashes of strategy logic string ID
    function strategyLogicIdHashes() external view returns (bytes32[] memory);

    // todo remove, use new function without calculating vault symbol on the fly for not initialized vaults
    // factory required that special functionally only internally, not for interface
    function getStrategyData(
        string memory vaultType,
        address strategyAddress,
        address
    )
        external
        view
        returns (
            string memory strategyId,
            address[] memory assets,
            string[] memory assetsSymbols,
            string memory specificName,
            string memory vaultSymbol
        );

    /// @dev Get best asset of assets to be strategy exchange asset
    function getExchangeAssetIndex(address[] memory assets) external view returns (uint);

    /// @notice Deployment key of created vault
    /// @param deploymentKey_ Hash of concatenated unique vault and strategy initialization parameters
    /// @return Address of deployed vault
    function deploymentKey(bytes32 deploymentKey_) external view returns (address);

    /// @notice Calculating deployment key based on unique vault and strategy initialization parameters
    /// @param vaultType Vault type string
    /// @param strategyId Strategy logic Id string
    /// @param vaultInitAddresses Vault initialization addresses for deployVaultAndStrategy method
    /// @param vaultInitNums Vault initialization uint numbers for deployVaultAndStrategy method
    /// @param strategyInitAddresses Strategy initialization addresses for deployVaultAndStrategy method
    /// @param strategyInitNums Strategy initialization uint numbers for deployVaultAndStrategy method
    /// @param strategyInitTicks Strategy initialization int24 ticks for deployVaultAndStrategy method
    function getDeploymentKey(
        string memory vaultType,
        string memory strategyId,
        address[] memory vaultInitAddresses,
        uint[] memory vaultInitNums,
        address[] memory strategyInitAddresses,
        uint[] memory strategyInitNums,
        int24[] memory strategyInitTicks
    ) external view returns (bytes32);

    /// @notice Governance and multisig can set a vault status other than Active - the default status.
    /// HardWorker only works with active vaults.
    /// @return status Constant from VaultStatusLib
    function vaultStatus(address vault) external view returns (uint status);

    /// @notice Check that strategy proxy deployed by the Factory
    /// @param address_ Address of contract
    /// @return This address is our strategy proxy
    function isStrategy(address address_) external view returns (bool);

    /// @notice Data on all factory strategies.
    /// The output values are matched by index in the arrays.
    /// @return id Strategy logic ID strings
    /// @return deployAllowed New vaults can be deployed
    /// @return upgradeAllowed Strategy can be upgraded
    /// @return farming It is farming strategy (earns farming/gauge rewards)
    /// @return tokenId Token ID of StrategyLogic NFT
    /// @return tokenURI StrategyLogic NFT tokenId metadata and on-chain image
    /// @return extra Strategy color, background color and other extra data
    function strategies()
        external
        view
        returns (
            string[] memory id,
            bool[] memory deployAllowed,
            bool[] memory upgradeAllowed,
            bool[] memory farming,
            uint[] memory tokenId,
            string[] memory tokenURI,
            bytes32[] memory extra
        );

    /// @notice Get config of vault type
    /// @param typeHash Keccak256 hash of vault type string
    /// @return vaultType Vault type string
    /// @return implementation Vault implementation address
    /// @return deployAllowed New vaults can be deployed
    /// @return upgradeAllowed Vaults can be upgraded
    /// @return buildingPrice Price of building new vault
    function vaultConfig(bytes32 typeHash)
        external
        view
        returns (
            string memory vaultType,
            address implementation,
            bool deployAllowed,
            bool upgradeAllowed,
            uint buildingPrice
        );

    /// @notice Data on all factory vault types
    /// The output values are matched by index in the arrays.
    /// @return vaultType Vault type string
    /// @return implementation Address of vault implemented logic
    /// @return deployAllowed New vaults can be deployed
    /// @return upgradeAllowed Vaults can be upgraded
    /// @return buildingPrice  Price of building new vault
    /// @return extra Vault type color, background color and other extra data
    function vaultTypes()
        external
        view
        returns (
            string[] memory vaultType,
            address[] memory implementation,
            bool[] memory deployAllowed,
            bool[] memory upgradeAllowed,
            uint[] memory buildingPrice,
            bytes32[] memory extra
        );

    /// @notice Initialization strategy params store
    function strategyAvailableInitParams(bytes32 idHash) external view returns (StrategyAvailableInitParams memory);

    //endregion -- View functions -----

    //region ----- Write functions -----

    /// @notice Main method of the Factory - new vault creation by user.
    /// @param vaultType Vault type ID string
    /// @param strategyId Strategy logic ID string
    /// Different types of vaults and strategies have different lengths of input arrays.
    /// @param vaultInitAddresses Addresses for vault initialization
    /// @param vaultInitNums Numbers for vault initialization
    /// @param strategyInitAddresses Addresses for strategy initialization
    /// @param strategyInitNums Numbers for strategy initialization
    /// @param strategyInitTicks Ticks for strategy initialization
    /// @return vault Deployed VaultProxy address
    /// @return strategy Deployed StrategyProxy address
    function deployVaultAndStrategy(
        string memory vaultType,
        string memory strategyId,
        address[] memory vaultInitAddresses,
        uint[] memory vaultInitNums,
        address[] memory strategyInitAddresses,
        uint[] memory strategyInitNums,
        int24[] memory strategyInitTicks
    ) external returns (address vault, address strategy);

    /// @notice Upgrade vault proxy. Can be called by any address.
    /// @param vault Address of vault proxy for upgrade
    function upgradeVaultProxy(address vault) external;

    /// @notice Upgrade strategy proxy. Can be called by any address.
    /// @param strategy Address of strategy proxy for upgrade
    function upgradeStrategyProxy(address strategy) external;

    /// @notice Add farm to factory
    /// @param farms_ Settings and data required to work with the farm.
    function addFarms(Farm[] memory farms_) external;

    /// @notice Update farm
    /// @param id Farm index
    /// @param farm_ Settings and data required to work with the farm.
    function updateFarm(uint id, Farm memory farm_) external;

    /// @notice Initial addition or change of vault type implementation
    /// Operator can add new vault type. Governance or multisig can change existing vault type config.
    /// @param vaultType Vault type string ID (Compounding, etc)
    /// @param implementation Address of vault implementation
    function setVaultImplementation(string memory vaultType, address implementation) external;

    /// @notice Governance and multisig can set a vault status other than Active - the default status.
    /// @param vaults Addresses of vault proxy
    /// @param statuses New vault statuses. Constant from VaultStatusLib
    function setVaultStatus(address[] memory vaults, uint[] memory statuses) external;

    /// @notice Initial addition or change of strategy available init params
    /// @param id Strategy ID string
    /// @param initParams Init params variations that will be parsed by strategy
    function setStrategyAvailableInitParams(string memory id, StrategyAvailableInitParams memory initParams) external;

    /// @notice Set new implementation of the strategy
    /// @dev Initial addition or change of strategy logic implementation.
    /// Operator can add new strategy logic. Governance or multisig can change existing logic config.
    /// @param strategyId Strategy logic ID string
    /// @param implementation Address of strategy implementation
    function setStrategyImplementation(string memory strategyId, address implementation) external;

    //endregion -- Write functions -----
}
