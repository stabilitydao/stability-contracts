// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Interface of the main contract and entry point to the platform.
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
interface IPlatform {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error AlreadyAnnounced();
    error SameVersion();
    error NoNewVersion();
    error UpgradeTimerIsNotOver(uint TimerTimestamp);
    error IncorrectFee(uint minFee, uint maxFee);
    error NotEnoughAllowedBBToken();
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
        address buildingPermitToken_,
        address vaultManager_,
        address strategyLogic_,
        address aprOracle_,
        address hardWorker,
        address rebalancer,
        address zap,
        address bridge
    );
    event OperatorAdded(address operator);
    event OperatorRemoved(address operator);
    event FeesChanged(uint fee, uint feeShareVaultManager, uint feeShareStrategyLogic, uint feeShareEcosystem);
    event MinInitialBoostChanged(uint minInitialBoostPerDay, uint minInitialBoostDuration);
    event NewAmmAdapter(string id, address proxy);
    event EcosystemRevenueReceiver(address receiver);
    event SetAllowedBBTokenVaults(address bbToken, uint vaultsToBuild, bool firstSet);
    event RemoveAllowedBBToken(address bbToken);
    event AddAllowedBoostRewardToken(address token);
    event RemoveAllowedBoostRewardToken(address token);
    event AddDefaultBoostRewardToken(address token);
    event RemoveDefaultBoostRewardToken(address token);
    event AddBoostTokens(address[] allowedBoostRewardToken, address[] defaultBoostRewardToken);
    event AllowedBBTokenVaultUsed(address bbToken, uint vaultToUse);
    event AddDexAggregator(address router);
    event RemoveDexAggregator(address router);
    event MinTvlForFreeHardWorkChanged(uint oldValue, uint newValue);
    event CustomVaultFee(address vault, uint platformFee);
    event Rebalancer(address rebalancer_);
    event Bridge(address bridge_);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

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

    struct AmmAdapter {
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
        address zap;
        address bridge;
        address rebalancer;
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

    /// @notice This NFT allow user to build limited number of vaults per week
    function buildingPermitToken() external view returns (address);

    /// @notice This ERC20 token is used as payment token for vault building
    function buildingPayPerVaultToken() external view returns (address);

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

    /// @notice Providing underlying assets APRs on-chain
    /// @return Address of AprOracle proxy
    function aprOracle() external view returns (address);

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

    /// @notice Stability Bridge
    /// @return Address of Bridge proxy
    function bridge() external view returns (address);

    /// @notice Name of current EVM network
    function networkName() external view returns (string memory);

    /// @notice Minimal initial boost rewards per day USD amount which needs to create rewarding vault
    function minInitialBoostPerDay() external view returns (uint);

    /// @notice Minimal boost rewards vesting duration for initial boost
    function minInitialBoostDuration() external view returns (uint);

    /// @notice This function provides the timestamp of the platform upgrade timelock.
    /// @dev This function is an external view function, meaning it doesn't modify the state.
    /// @return uint representing the timestamp of the platform upgrade timelock.
    function platformUpgradeTimelock() external view returns (uint);

    /// @dev Extra network data
    /// @return 0-2 bytes - color
    ///         3-5 bytes - background color
    ///         6-31 bytes - free
    function networkExtra() external view returns (bytes32);

    /// @notice Pending platform upgrade data
    function pendingPlatformUpgrade() external view returns (PlatformUpgrade memory);

    /// @notice Get platform revenue fee settings
    /// @return fee Revenue fee % (between MIN_FEE - MAX_FEE) with DENOMINATOR precision.
    /// @return feeShareVaultManager Revenue fee share % of VaultManager tokenId owner
    /// @return feeShareStrategyLogic Revenue fee share % of StrategyLogic tokenId owner
    /// @return feeShareEcosystem Revenue fee share % of ecosystemFeeReceiver
    function getFees()
        external
        view
        returns (uint fee, uint feeShareVaultManager, uint feeShareStrategyLogic, uint feeShareEcosystem);

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

    /// @notice Allowed buy-back tokens for rewarding vaults
    function allowedBBTokens() external view returns (address[] memory);

    /// @notice Vaults building limit for buy-back token.
    /// This limit decrements when a vault for BB-token is built.
    /// @param token Allowed buy-back token
    /// @return vaultsLimit Number of vaults that can be built for BB-token
    function allowedBBTokenVaults(address token) external view returns (uint vaultsLimit);

    /// @notice Vaults building limits for allowed buy-back tokens.
    /// @return bbToken Allowed buy-back tokens
    /// @return vaultsLimit Number of vaults that can be built for BB-tokens
    function allowedBBTokenVaults() external view returns (address[] memory bbToken, uint[] memory vaultsLimit);

    /// @notice Non-zero vaults building limits for allowed buy-back tokens.
    /// @return bbToken Allowed buy-back tokens
    /// @return vaultsLimit Number of vaults that can be built for BB-tokens
    function allowedBBTokenVaultsFiltered()
        external
        view
        returns (address[] memory bbToken, uint[] memory vaultsLimit);

    /// @notice Check address for existance in operators list
    /// @param operator Address
    /// @return True if this address is Stability Operator
    function isOperator(address operator) external view returns (bool);

    /// @notice Tokens that can be used for boost rewards of rewarding vaults
    /// @return Addresses of tokens
    function allowedBoostRewardTokens() external view returns (address[] memory);

    /// @notice Allowed boost reward tokens that used for unmanaged rewarding vaults creation
    /// @return Addresses of tokens
    function defaultBoostRewardTokens() external view returns (address[] memory);

    /// @notice Allowed boost reward tokens that used for unmanaged rewarding vaults creation
    /// @param addressToRemove This address will be removed from default boost reward tokens
    /// @return Addresses of tokens
    function defaultBoostRewardTokensFiltered(address addressToRemove) external view returns (address[] memory);

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
    ///        platformAddresses[3] buildingPermitToken
    ///        platformAddresses[4] buildingPayPerVaultToken
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

    // todo add vaultSymbol, vaultName
    /// @notice Front-end balances, prices and vault list viewer
    /// @param yourAccount Address of account to query balances
    /// @return token Tokens supported by the platform
    /// @return tokenPrice USD price of token. Index of token same as in previous array.
    /// @return tokenUserBalance User balance of token. Index of token same as in previous array.
    /// @return vault Deployed vaults
    /// @return vaultSharePrice Price 1.0 vault share. Index of vault same as in previous array.
    /// @return vaultUserBalance User balance of vault. Index of vault same as in previous array.
    /// @return nft Ecosystem NFTs
    ///         nft[0] BuildingPermitToken
    ///         nft[1] VaultManager
    ///         nft[2] StrategyLogic
    /// @return nftUserBalance User balance of NFT. Index of NFT same as in previous array.
    /// @return buildingPayPerVaultTokenBalance User balance of vault creation paying token
    function getBalance(address yourAccount)
        external
        view
        returns (
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
    /// Only operator (multisig is operator too) can ececute pending platform upgrade
    function upgrade() external;

    /// @notice Cancel pending platform upgrade
    /// Only operator (multisig is operator too) can ececute pending platform upgrade
    function cancelUpgrade() external;

    /// @notice Register AMM adapter in platform
    /// @param id AMM adapter ID string from AmmAdapterIdLib
    /// @param proxy Address of AMM adapter proxy
    function addAmmAdapter(string memory id, address proxy) external;

    // todo Only governance and multisig can set allowed bb-token vaults building limit
    /// @notice Set new vaults building limit for buy-back token
    /// @param bbToken Address of allowed buy-back token
    /// @param vaultsToBuild Number of vaults that can be built for BB-token
    function setAllowedBBTokenVaults(address bbToken, uint vaultsToBuild) external;

    // todo Only governance and multisig can add allowed boost reward token
    /// @notice Add new allowed boost reward token
    /// @param token Address of token
    function addAllowedBoostRewardToken(address token) external;

    // todo Only governance and multisig can remove allowed boost reward token
    /// @notice Remove allowed boost reward token
    /// @param token Address of allowed boost reward token
    function removeAllowedBoostRewardToken(address token) external;

    // todo Only governance and multisig can add default boost reward token
    /// @notice Add default boost reward token
    /// @param token Address of default boost reward token
    function addDefaultBoostRewardToken(address token) external;

    // todo Only governance and multisig can remove default boost reward token
    /// @notice Remove default boost reward token
    /// @param token Address of allowed boost reward token
    function removeDefaultBoostRewardToken(address token) external;

    // todo Only governance and multisig can add allowed boost reward token
    // todo Only governance and multisig can add default boost reward token
    /// @notice Add new allowed boost reward token
    /// @notice Add default boost reward token
    /// @param allowedBoostRewardToken Address of allowed boost reward token
    /// @param defaultBoostRewardToken Address of default boost reward token
    function addBoostTokens(
        address[] memory allowedBoostRewardToken,
        address[] memory defaultBoostRewardToken
    ) external;

    /// @notice Decrease allowed BB-token vault building limit when vault is built
    /// Only Factory can do it.
    /// @param bbToken Address of allowed buy-back token
    function useAllowedBBTokenVault(address bbToken) external;

    /// @notice Allow DeX aggregator routers to be used in the platform
    /// @param dexAggRouter Addresses of DeX aggreagator routers
    function addDexAggregators(address[] memory dexAggRouter) external;

    /// @notice Remove allowed DeX aggregator router from the platform
    /// @param dexAggRouter Address of DeX aggreagator router
    function removeDexAggregator(address dexAggRouter) external;

    /// @notice Change initial boost rewards settings
    /// @param minInitialBoostPerDay_ Minimal initial boost rewards per day USD amount which needs to create rewarding vault
    /// @param minInitialBoostDuration_ Minimal boost rewards vesting duration for initial boost
    function setInitialBoost(uint minInitialBoostPerDay_, uint minInitialBoostDuration_) external;

    /// @notice Update new minimum TVL for compensate.
    /// @param value New minimum TVL for compensate.
    function setMinTvlForFreeHardWork(uint value) external;

    /// @notice Set custom platform fee for vault
    /// @param vault Vault address
    /// @param platformFee Custom platform fee
    function setCustomVaultFee(address vault, uint platformFee) external;

    /// @notice Setup Rebalancer.
    /// Only Goverannce or Multisig can do this when Rebalancer is not set.
    /// @param rebalancer_ Proxy address of Bridge
    function setupRebalancer(address rebalancer_) external;

    /// @notice Setup Bridge.
    /// Only Goverannce or Multisig can do this when Bridge is not set.
    /// @param bridge_ Proxy address of Bridge
    function setupBridge(address bridge_) external;
}
