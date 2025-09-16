// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Interface of the main contract and entry point to the platform.
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
/// @author ruby (https://github.com/alexandersazonof)
interface IPlatform {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error AlreadyAnnounced();
    error SameVersion();
    error NoNewVersion();
    error UpgradeTimerIsNotOver(uint TimerTimestamp);
    error IncorrectFee(uint minFee, uint maxFee);
    error TokenAlreadyExistsInSet(address token);
    error AggregatorNotExists(address dexAggRouter);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event PlatformVersion(string version);
    event UpgradeAnnounce(
        string oldVersion, string newVersion, address[] proxies, address[] newImplementations, uint timelock
    );
    event CancelUpgrade(string oldVersion, string newVersion);
    event ProxyUpgraded(
        address indexed proxy, address implementation, string oldContractVersion, string newContractVersion
    );
    event Addresses(
        address multisig_,
        address factory_,
        address priceReader_,
        address swapper_,
        address,
        address vaultManager_,
        address strategyLogic_,
        address,
        address hardWorker,
        address rebalancer,
        address zap,
        address bridge
    );
    event OperatorAdded(address operator);
    event OperatorRemoved(address operator);
    event FeesChanged(uint fee, uint, uint, uint);
    event NewAmmAdapter(string id, address proxy);
    event EcosystemRevenueReceiver(address receiver);
    event AddDexAggregator(address router);
    event RemoveDexAggregator(address router);
    event MinTvlForFreeHardWorkChanged(uint oldValue, uint newValue);
    event CustomVaultFee(address vault, uint platformFee);
    event Rebalancer(address rebalancer_);
    event Bridge(address bridge_);
    event RevenueRouter(address revenueRouter_);
    event MetaVaultFactory(address metaVaultFactory);
    event VaultPriceOracle(address vaultPriceOracle_);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct PlatformUpgrade {
        string newVersion;
        address[] proxies;
        address[] newImplementations;
    }

    struct PlatformSettings {
        uint fee;
    }

    struct AmmAdapter {
        string id;
        address proxy;
    }

    struct SetupAddresses {
        address factory;
        address priceReader;
        address swapper;
        address vaultManager;
        address strategyLogic;
        address targetExchangeAsset;
        address hardWorker;
        address zap;
        address revenueRouter;
        address metaVaultFactory;
        address vaultPriceOracle;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Platform version in CalVer scheme: YY.MM.MINOR-tag. Updates on core contract upgrades.
    function platformVersion() external view returns (string memory);

    /// @notice Time delay for proxy upgrades of core contracts and changing important platform settings by multisig
    //slither-disable-next-line naming-convention
    function TIME_LOCK() external view returns (uint);

    /// @notice DAO governance
    function governance() external view returns (address);

    /// @notice Core team multi signature wallet. Development and operations fund
    function multisig() external view returns (address);

    /// @notice Receiver of ecosystem revenue
    function ecosystemRevenueReceiver() external view returns (address);

    /// @dev The best asset in a network for swaps between strategy assets and farms rewards assets
    ///      The target exchange asset is used for finding the best strategy's exchange asset.
    ///      Rhe fewer routes needed to swap to the target exchange asset, the better.
    function targetExchangeAsset() external view returns (address);

    /// @notice Platform factory assembling vaults. Stores settings, strategy logic, farms.
    /// Provides the opportunity to upgrade vaults and strategies.
    /// @return Address of Factory proxy
    function factory() external view returns (address);

    /// @notice The holders of these NFT receive a share of the vault revenue
    /// @return Address of VaultManager proxy
    function vaultManager() external view returns (address);

    /// @notice The holders of these tokens receive a share of the revenue received in all vaults using this strategy logic.
    function strategyLogic() external view returns (address);

    /// @notice Combining oracle and DeX spot prices
    /// @return Address of PriceReader proxy
    function priceReader() external view returns (address);

    /// @notice On-chain price quoter and swapper
    /// @return Address of Swapper proxy
    function swapper() external view returns (address);

    /// @notice HardWork resolver and caller
    /// @return Address of HardWorker proxy
    function hardWorker() external view returns (address);

    /// @notice Rebalance resolver
    /// @return Address of Rebalancer proxy
    function rebalancer() external view returns (address);

    /// @notice ZAP feature
    /// @return Address of Zap proxy
    function zap() external view returns (address);

    /// @notice Platform revenue distributor
    /// @return Address of the revenue distributor proxy
    function revenueRouter() external view returns (address);

    /// @notice Factory of MetaVaults
    /// @return Address of the MetaVault factory
    function metaVaultFactory() external view returns (address);

    /// @notice vaultPriceOracle
    /// @return Address of the vault price oracle
    function vaultPriceOracle() external view returns (address);

    /// @notice This function provides the timestamp of the platform upgrade timelock.
    /// @dev This function is an external view function, meaning it doesn't modify the state.
    /// @return uint representing the timestamp of the platform upgrade timelock.
    function platformUpgradeTimelock() external view returns (uint);

    /// @notice Pending platform upgrade data
    function pendingPlatformUpgrade() external view returns (PlatformUpgrade memory);

    /// @notice Get platform revenue fee settings
    /// @return fee Revenue fee % (between MIN_FEE - MAX_FEE) with DENOMINATOR precision.
    function getFees() external view returns (uint fee, uint, uint, uint);

    /// @notice Get custom vault platform fee
    /// @return fee revenue fee % with DENOMINATOR precision
    function getCustomVaultFee(address vault) external view returns (uint fee);

    /// @notice Platform settings
    function getPlatformSettings() external view returns (PlatformSettings memory);

    /// @notice AMM adapters of the platform
    function getAmmAdapters() external view returns (string[] memory id, address[] memory proxy);

    /// @notice Get AMM adapter data by hash
    /// @param ammAdapterIdHash Keccak256 hash of adapter ID string
    /// @return ID string and proxy address of AMM adapter
    function ammAdapter(bytes32 ammAdapterIdHash) external view returns (AmmAdapter memory);

    /// @notice Check address for existance in operators list
    /// @param operator Address
    /// @return True if this address is Stability Operator
    function isOperator(address operator) external view returns (bool);

    /// @notice Allowed DeX aggregators
    /// @return Addresses of DeX aggregator rounters
    function dexAggregators() external view returns (address[] memory);

    /// @notice DeX aggregator router address is allowed to be used in the platform
    /// @param dexAggRouter Address of DeX aggreagator router
    /// @return Can be used
    function isAllowedDexAggregatorRouter(address dexAggRouter) external view returns (bool);

    /// @notice Show minimum TVL for compensate if vault has not enough ETH
    /// @return Minimum TVL for compensate.
    function minTvlForFreeHardWork() external view returns (uint);

    /// @notice Front-end platform viewer
    /// @return platformAddresses Platform core addresses
    ///        platformAddresses[0] factory
    ///        platformAddresses[1] vaultManager
    ///        platformAddresses[2] strategyLogic
    ///        platformAddresses[3] deprecated
    ///        platformAddresses[4] deprecated
    ///        platformAddresses[5] governance
    ///        platformAddresses[6] multisig
    ///        platformAddresses[7] zap
    ///        platformAddresses[8] bridge
    /// @return bcAssets Blue chip token addresses
    /// @return dexAggregators_ DeX aggregators allowed to be used entire the platform
    /// @return vaultType Vault type ID strings
    /// @return vaultExtra Vault color, background color and other extra data. Index of vault same as in previous array.
    /// @return vaultBulldingPrice Price of creating new vault in buildingPayPerVaultToken. Index of vault same as in previous array.
    /// @return strategyId Strategy logic ID strings
    /// @return isFarmingStrategy True if strategy is farming strategy. Index of strategy same as in previous array.
    /// @return strategyTokenURI StrategyLogic NFT tokenId metadata and on-chain image. Index of strategy same as in previous array.
    /// @return strategyExtra Strategy color, background color and other extra data. Index of strategy same as in previous array.
    function getData()
        external
        view
        returns (
            address[] memory platformAddresses,
            address[] memory bcAssets,
            address[] memory dexAggregators_,
            string[] memory vaultType,
            bytes32[] memory vaultExtra,
            uint[] memory vaultBulldingPrice,
            string[] memory strategyId,
            bool[] memory isFarmingStrategy,
            string[] memory strategyTokenURI,
            bytes32[] memory strategyExtra
        );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Add platform operator.
    /// Only governance and multisig can add operator.
    /// @param operator Address of new operator
    function addOperator(address operator) external;

    /// @notice Remove platform operator.
    /// Only governance and multisig can remove operator.
    /// @param operator Address of operator to remove
    function removeOperator(address operator) external;

    /// @notice Announce upgrade of platform proxies implementations
    /// Only governance and multisig can announce platform upgrades.
    /// @param newVersion New platform version. Version must be changed when upgrading.
    /// @param proxies Addresses of core contract proxies
    /// @param newImplementations New implementation for proxy. Index of proxy same as in previous array.
    function announcePlatformUpgrade(
        string memory newVersion,
        address[] memory proxies,
        address[] memory newImplementations
    ) external;

    /// @notice Upgrade platform
    /// Only operator (multisig is operator too) can execute pending platform upgrade
    function upgrade() external;

    /// @notice Cancel pending platform upgrade
    /// Only operator (multisig is operator too) can execute pending platform upgrade
    function cancelUpgrade() external;

    /// @notice Register AMM adapter in platform
    /// @param id AMM adapter ID string from AmmAdapterIdLib
    /// @param proxy Address of AMM adapter proxy
    function addAmmAdapter(string memory id, address proxy) external;

    /// @notice Allow DeX aggregator routers to be used in the platform
    /// @param dexAggRouter Addresses of DeX aggreagator routers
    function addDexAggregators(address[] memory dexAggRouter) external;

    /// @notice Remove allowed DeX aggregator router from the platform
    /// @param dexAggRouter Address of DeX aggreagator router
    function removeDexAggregator(address dexAggRouter) external;

    /// @notice Update new minimum TVL for compensate.
    /// @param value New minimum TVL for compensate.
    function setMinTvlForFreeHardWork(uint value) external;

    /// @notice Set custom platform fee for vault
    /// @param vault Vault address
    /// @param platformFee Custom platform fee
    function setCustomVaultFee(address vault, uint platformFee) external;

    /// @notice Set vault price oracle
    /// @param vaultPriceOracle_ Address of the vault price oracle
    function setupVaultPriceOracle(address vaultPriceOracle_) external;
}
