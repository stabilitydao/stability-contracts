// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @notice Creating vaults, upgrading vaults and strategies, vault list, farms and strategy logics management
/// @author Alien Deployer (https://github.com/a17)
interface IFactory {
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
    event StrategyProxyUpgraded(
        address proxy,
        address oldImplementation,
        address newImplementation
    );
    event VaultProxyUpgraded(
        address proxy,
        address oldImplementation,
        address newImplementation
    );
    event VaultConfigChanged(
        string type_,
        address implementation,
        bool deployAllowed,
        bool upgradeAllowed
    );
    event StrategyLogicConfigChanged(
        string id,
        address implementation,
        bool deployAllowed,
        bool upgradeAllowed
    );
    event VaultStatus(address indexed vault, uint newStatus);

    //endregion -- Events -----

    //region ----- Data types -----

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

    //endregion -- Data types -----
    
    //region ----- View functions -----

    function deployedVaults() external view returns (address[] memory);

    function deployedVault(uint id) external view returns (address);

    function farms() external view returns (Farm[] memory);

    function farm(uint id) external view returns (Farm memory);

    function strategyLogicConfig(bytes32 idHash) external view returns (
        string memory id,
        address implementation,
        bool deployAllowed,
        bool upgradeAllowed,
        bool farming,
        uint tokenId
    );

    function strategyLogicIdHashes() external view returns (bytes32[] memory);

    function getStrategyData(string memory vaultType, address strategyAddress, address bbAsset) external view returns (
        string memory strategyId,
        address[] memory assets,
        string[] memory assetsSymbols,
        string memory specificName,
        string memory vaultSymbol
    );

    /// @dev Get best asset of assets to be strategy exchange asset
    function getExchangeAssetIndex(address[] memory assets) external view returns (uint);

    function deploymentKey(bytes32 deploymentKey_) external view returns (address);

    function whatToBuild() external view returns (
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

    function vaultStatus(address vault) external view returns (uint status);

    function strategies() external view returns (
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
    /// @return buildingPrice  Price of building new vault
    function vaultConfig(bytes32 typeHash) external view returns (
        string memory vaultType,
        address implementation,
        bool deployAllowed,
        bool upgradeAllowed,
        uint buildingPrice
    );
    
    function vaultTypes() external view returns (
        string[] memory vaultType,
        bool[] memory deployAllowed,
        bool[] memory upgradeAllowed,
        uint[] memory buildingPrice,
        bytes32[] memory extra
    );

    //endregion -- View functions -----

    //region ----- Write functions -----

    function deployVaultAndStrategy(
        string memory vaultType,
        string memory strategyId,
        address[] memory vaultInitAddresses,
        uint[] memory vaultInitNums,
        address[] memory strategyInitAddresses,
        uint[] memory strategyInitNums,
        int24[] memory strategyInitTicks
    ) external returns (address vault, address strategy);

    function upgradeVaultProxy(address vault) external;

    function upgradeStrategyProxy(address strategy) external;

    function addFarm(Farm memory farm_) external;

    function setVaultConfig(VaultConfig memory vaultConfig_) external;

    function setStrategyLogicConfig(StrategyLogicConfig memory config, address developer) external;

    //endregion -- Write functions -----
}
