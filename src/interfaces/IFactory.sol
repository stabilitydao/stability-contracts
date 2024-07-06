// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @notice Creating vaults, upgrading vaults and strategies, vault list, farms and strategy logics management
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
/// @author HCrypto7 (https://github.com/hcrypto7)
interface IFactory {
    //region ----- Custom Errors -----

    error VaultImplementationIsNotAvailable();
    error VaultNotAllowedToDeploy();
    error StrategyImplementationIsNotAvailable();
    error StrategyLogicNotAllowedToDeploy();
    error YouDontHaveEnoughTokens(uint userBalance, uint requireBalance, address payToken);
    error SuchVaultAlreadyDeployed(bytes32 key);
    error NotActiveVault();
    error UpgradeDenied(bytes32 _hash);
    error AlreadyLastVersion(bytes32 _hash);
    error NotStrategy();
    error BoostDurationTooLow();
    error BoostAmountTooLow();
    error BoostAmountIsZero();

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
        mapping(uint week => mapping(uint builderPermitTokenId => uint vaultsBuilt)) vaultsBuiltByPermitTokenId;
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
        address bbAsset
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
    /// @param vaultInitAddresses Vault initizlization addresses for deployVaultAndStrategy method
    /// @param vaultInitNums Vault initizlization uint numbers for deployVaultAndStrategy method
    /// @param strategyInitAddresses Strategy initizlization addresses for deployVaultAndStrategy method
    /// @param strategyInitNums Strategy initizlization uint numbers for deployVaultAndStrategy method
    /// @param strategyInitTicks Strategy initizlization int24 ticks for deployVaultAndStrategy method
    function getDeploymentKey(
        string memory vaultType,
        string memory strategyId,
        address[] memory vaultInitAddresses,
        uint[] memory vaultInitNums,
        address[] memory strategyInitAddresses,
        uint[] memory strategyInitNums,
        int24[] memory strategyInitTicks
    ) external returns (bytes32);

    /// @notice Available variants of new vault for creating.
    /// The structure of the function's output values is complex,
    /// but after parsing them, the front end has all the data to generate a list of vaults to create.
    /// @return desc Descriptions of the strategy for making money
    /// @return vaultType Vault type strings. Output values are matched by index with previous array.
    /// @return strategyId Strategy logic ID strings. Output values are matched by index with previous array.
    /// @return initIndexes Map of start and end indexes in next 5 arrays. Output values are matched by index with previous array.
    ///                 [0] Start index in vaultInitAddresses
    ///                 [1] End index in vaultInitAddresses
    ///                 [2] Start index in vaultInitNums
    ///                 [3] End index in vaultInitNums
    ///                 [4] Start index in strategyInitAddresses
    ///                 [5] End index in strategyInitAddresses
    ///                 [6] Start index in strategyInitNums
    ///                 [7] End index in strategyInitNums
    ///                 [8] Start index in strategyInitTicks
    ///                 [9] End index in strategyInitTicks
    /// @return vaultInitAddresses Vault initizlization addresses for deployVaultAndStrategy method for all building variants.
    /// @return vaultInitNums Vault initizlization uint numbers for deployVaultAndStrategy method for all building variants.
    /// @return strategyInitAddresses Strategy initizlization addresses for deployVaultAndStrategy method for all building variants.
    /// @return strategyInitNums Strategy initizlization uint numbers for deployVaultAndStrategy method for all building variants.
    /// @return strategyInitTicks Strategy initizlization int24 ticks for deployVaultAndStrategy method for all building variants.
    function whatToBuild()
        external
        view
        returns (
            string[] memory desc,
            string[] memory vaultType,
            string[] memory strategyId,
            uint[10][] memory initIndexes,
            address[] memory vaultInitAddresses,
            uint[] memory vaultInitNums,
            address[] memory strategyInitAddresses,
            uint[] memory strategyInitNums,
            int24[] memory strategyInitTicks
        );

    /// @notice Governance and multisig can set a vault status other than Active - the default status.
    /// HardWorker only works with active vaults.
    /// @return status Constant from VaultStatusLib
    function vaultStatus(address vault) external view returns (uint status);

    /// @notice Check that strategy proxy deployed by the Factory
    /// @param address_ Address of contract
    /// @return This address is our strategy proxy
    function isStrategy(address address_) external view returns (bool);

    /// @notice How much vaults was built by builderPermitToken NFT tokenId in week
    /// @param week Week index (timestamp / (86400 * 7))
    /// @param builderPermitTokenId Token ID of buildingPermitToken NFT
    /// @return vaultsBuilt Vaults built
    function vaultsBuiltByPermitTokenId(
        uint week,
        uint builderPermitTokenId
    ) external view returns (uint vaultsBuilt);

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

    /// @notice Retrieves the alias name associated with a given address
    /// @param tokenAddress_ The address to query for its alias name
    /// @return The alias name associated with the provided address
    function getAliasName(address tokenAddress_) external view returns (string memory);

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

    /// @notice Initial addition or change of vault type settings.
    /// Operator can add new vault type. Governance or multisig can change existing vault type config.
    /// @param vaultConfig_ Vault type settings
    function setVaultConfig(VaultConfig memory vaultConfig_) external;

    /// @notice Initial addition or change of strategy logic settings.
    /// Operator can add new strategy logic. Governance or multisig can change existing logic config.
    /// @param config Strategy logic settings
    /// @param developer Strategy developer is receiver of minted StrategyLogic NFT on initial addition
    function setStrategyLogicConfig(StrategyLogicConfig memory config, address developer) external;

    /// @notice Governance and multisig can set a vault status other than Active - the default status.
    /// @param vaults Addresses of vault proxy
    /// @param statuses New vault statuses. Constant from VaultStatusLib
    function setVaultStatus(address[] memory vaults, uint[] memory statuses) external;

    /// @notice Initial addition or change of strategy available init params
    /// @param id Strategy ID string
    /// @param initParams Init params variations that will be parsed by strategy
    function setStrategyAvailableInitParams(string memory id, StrategyAvailableInitParams memory initParams) external;

    /// @notice Assigns a new alias name to a specific address
    /// @dev This function may require certain permissions to be called successfully.
    /// @param tokenAddress_ The address to assign an alias name to
    /// @param aliasName_ The alias name to assign to the given address
    function setAliasName(address tokenAddress_, string memory aliasName_) external;

    //endregion -- Write functions -----
}
