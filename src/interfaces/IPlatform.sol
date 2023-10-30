// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @notice The main contract and entry point to the platform.
///         It stores the addresses of infrastructure contracts, list of operators, settings
///         and allows to upgrade platform core contracts.
/// @author Alien Deployer (https://github.com/a17)
interface IPlatform {
    //region ----- Events -----
    event PlatformVersion(string version);
    event UpgradeAnnounce(string oldVersion, string newVersion, address[] proxies, address[] newImplementations, uint timelock);
    event CancelUpgrade(string oldVersion, string newVersion);
    event ProxyUpgraded(address indexed proxy, address implementation, string oldContractVersion, string newContractVersion);
    event Addresses(
        address multisig_,
        address factory_,
        address priceReader_,
        address swapper_,
        address buildingPermitToken_,
        address vaultManager_,
        address strategyLogic_,
        address aprOracle_,
        address hardWorker
    );
    event OperatorAdded(address operator);
    event OperatorRemoved(address operator);
    event FeesChanged(uint fee, uint feeShareVaultManager, uint feeShareStrategyLogic, uint feeShareEcosystem);
    event MinInitialBoostChanged(uint minInitialBoostPerDay, uint minInitialBoostDuration);
    event NewDexAdapter(string id, address proxy);
    //endregion -- Events -----

    //region ----- Data types -----
    struct PlatformUpgrade {
        string newVersion;
        address[] proxies;
        address[] newImplementations;
    }
    struct PlatformSettings {
        string networkName;
        bytes32 networkExtra;
        uint fee;
        uint feeShareVaultManager;
        uint feeShareStrategyLogic;
        uint feeShareEcosystem;
        uint minInitialBoostPerDay;
        uint minInitialBoostDuration;
    }
    struct DexAdapter {
        string id;
        address proxy;
    }
    struct SetupAddresses {
        address factory;
        address priceReader;
        address swapper;
        address buildingPermitToken;
        address buildingPayPerVaultToken;
        address vaultManager;
        address strategyLogic;
        address aprOracle;
        address targetExchangeAsset;
        address hardWorker;
    }
    //endregion -- Data types -----

    //region ----- View functions -----

    /// @notice Platform version in CalVer scheme: YY.MM.MINOR-tag. Updates on core contract upgrades.
    function PLATFORM_VERSION() external view returns (string memory);

    /// @notice Time delay for proxy upgrades of core contracts and changing important platform settings by multisig
    function TIME_LOCK() external view returns (uint);

    /// @notice DAO governance
    function governance() external view returns (address);

    /// @notice Core team multi signature wallet. Development and operations fund
    function multisig() external view returns (address);

    /// @notice Platform factory assembling vaults. Stores settings, strategy logic, farms.
    ///         Provides the opportunity to upgrade vaults and strategies.
    function factory() external view returns (address);

    /// @notice Combining oracle and DeX spot prices
    function priceReader() external view returns (address);

    /// @notice Providing underlying assets APRs on-chain
    function aprOracle() external view returns (address);

    /// @notice On-chain price quoter and swapper
    function swapper() external view returns (address);

    /// @notice The holders of these NFT receive a share of the vault revenue
    function vaultManager() external view returns (address);

    /// @notice The holders of these tokens receive a share of the revenue received in all vaults using this strategy logic.
    function strategyLogic() external view returns (address);

    /// @notice HardWork resolver and caller
    function hardWorker() external view returns (address);

    /// @notice This NFT allow user to build limited number of vaults per week
    function buildingPermitToken() external view returns (address);

    /// @notice This ERC20 token is used as payment token for vault building
    function buildingPayPerVaultToken() external view returns (address);

    /// @notice Receiver of ecosystem revenue
    function ecosystemRevenueReceiver() external view returns (address);

    /// @notice Name of current EVM network
    function networkName() external view returns (string memory);

    /// @notice Minimal initial boost rewards per day USD amount which needs to create rewarding vault
    function minInitialBoostPerDay() external view returns (uint);

    /// @notice Minimal boost rewards vesting duration for initial boost
    function minInitialBoostDuration() external view returns (uint);

    /// @dev Extra network data
    /// @return 0-2 bytes - color
    ///         3-5 bytes - background color
    ///         6-31 bytes - free
    function networkExtra() external view returns (bytes32);

    /// @dev The best asset in a network for swaps between strategy assets and farms rewards assets
    ///      The target exchange asset is used for finding the best strategy's exchange asset.
    ///      Rhe fewer routes needed to swap to the target exchange asset, the better.
    function targetExchangeAsset() external view returns (address);


    function pendingPlatformUpgrade() external view returns (PlatformUpgrade memory);

    /// @notice Get platform revenue fee settings
    /// @return fee Revenue fee % (between MIN_FEE - MAX_FEE) with DENOMINATOR precision.
    /// @return feeShareVaultManager Revenue fee share % of VaultManager tokenId owner
    /// @return feeShareStrategyLogic Revenue fee share % of StrategyLogic tokenId owner
    /// @return feeShareEcosystem Revenue fee share % of ecosystemFeeReceiver
    function getFees() external view returns (uint fee, uint feeShareVaultManager, uint feeShareStrategyLogic, uint feeShareEcosystem);

    function getPlatformSettings() external view returns (PlatformSettings memory);

    function getDexAdapters() external view returns(string[] memory id, address[] memory proxy);

    function dexAdapter(bytes32 dexAdapterIdHash) external view returns(DexAdapter memory);

    function allowedBBTokens() external view returns(address[] memory);

    function allowedBBTokenVaults(address token) external view returns (uint vaultsLimit);

    function allowedBBTokenVaults() external view returns (address[] memory bbToken, uint[] memory vaultsLimit);

    function allowedBBTokenVaultsFiltered() external view returns (address[] memory bbToken, uint[] memory vaultsLimit);

    function isOperator(address operator) external view returns (bool);

    function allowedBoostRewardTokens() external view returns(address[] memory);

    function defaultBoostRewardTokens() external view returns(address[] memory);

    function defaultBoostRewardTokensFiltered(address addressToRemove) external view returns(address[] memory);

    /// @notice Front-end platform viewer
    function getData() external view returns(
        address[] memory platformAddresses,
        string[] memory vaultType,
        bytes32[] memory vaultExtra,
        uint[] memory vaultBulldingPrice,
        string[] memory strategyId,
        bool[] memory isFarmingStrategy,
        string[] memory strategyTokenURI,
        bytes32[] memory strategyExtra
    );

    /// @notice Front-end balances and prices viewer
    function getBalance(address yourAccount) external view returns (
        address[] memory token,
        uint[] memory tokenPrice,
        uint[] memory tokenUserBalance,
        address[] memory vault,
        uint[] memory vaultSharePrice,
        uint[] memory vaultUserBalance,
        address[] memory nft,
        uint[] memory nftUserBalance,
        uint buildingPayPerVaultTokenBalance
    );

    //endregion -- View functions -----

    //region ----- Write functions -----

    function addOperator(address operator) external;

    function removeOperator(address operator) external;

    /// @dev Announce upgrade of proxies implementations by governance
    // function announceProxyUpgrade(
        // address[] memory proxies,
        // address[] memory implementations
    // ) external;

    /// @dev Announce upgrade of platform proxies implementations
    function announcePlatformUpgrade(
        string memory newVersion,
        address[] memory proxies,
        address[] memory newImplementations
    ) external;

    /// @dev Upgrade platform
    function upgrade() external;

    function cancelUpgrade() external;

    /// @dev Register DeX adapter
    function addDexAdapter(string memory id, address proxy) external;

    function setAllowedBBTokenVaults(address bbToken, uint vaultsToBuild) external;

    function useAllowedBBTokenVault(address bbToken) external;

    function addAllowedBoostRewardToken(address token) external;

    function removeAllowedBoostRewardToken(address token) external;

    function addDefaultBoostRewardToken(address token) external;

    function removeDefaultBoostRewardToken(address token) external;

    //endregion -- Write functions -----
}
