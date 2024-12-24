// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./base/Controllable.sol";
import "./libs/ConstantsLib.sol";
import "./libs/CommonLib.sol";
import "../interfaces/IPlatform.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/IProxy.sol";
import "../interfaces/ISwapper.sol";
import "../interfaces/IPriceReader.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/IVault.sol";

/// @notice The main contract of the platform.
///         It stores core and infrastructure addresses, list of operators, fee settings, allows plaform upgrades etc.
///         ┏┓┏┳┓┏┓┳┓┳┓ ┳┏┳┓┓┏  ┏┓┓ ┏┓┏┳┓┏┓┏┓┳┓┳┳┓
///         ┗┓ ┃ ┣┫┣┫┃┃ ┃ ┃ ┗┫  ┃┃┃ ┣┫ ┃ ┣ ┃┃┣┫┃┃┃
///         ┗┛ ┻ ┛┗┻┛┻┗┛┻ ┻ ┗┛  ┣┛┗┛┛┗ ┻ ┻ ┗┛┛┗┛ ┗
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
/// @author 0xhokugava (https://github.com/0xhokugava)
contract Platform is Controllable, IPlatform {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of Platform contract implementation
    string public constant VERSION = "1.1.0";

    /// @inheritdoc IPlatform
    uint public constant TIME_LOCK = 16 hours;

    /// @dev Minimal revenue fee
    uint public constant MIN_FEE = 5_000; // 5%

    /// @dev Maximal revenue fee
    uint public constant MAX_FEE = 50_000; // 50%

    /// @dev Minimal VaultManager tokenId owner fee share
    uint public constant MIN_FEE_SHARE_VAULT_MANAGER = 10_000; // 10%

    /// @dev Minimal StrategyLogic tokenId owner fee share
    uint public constant MIN_FEE_SHARE_STRATEGY_LOGIC = 10_000; // 10%

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.Platform")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant PLATFORM_STORAGE_LOCATION =
        0x263d5089de5bb3f97c8effd51f1a153b36e97065a51e67a94885830ed03a7a00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.Platform
    struct PlatformStorage {
        /// @inheritdoc IPlatform
        address governance;
        /// @inheritdoc IPlatform
        address multisig;
        /// @inheritdoc IPlatform
        address buildingPermitToken;
        /// @inheritdoc IPlatform
        address buildingPayPerVaultToken;
        /// @inheritdoc IPlatform
        address ecosystemRevenueReceiver;
        /// @inheritdoc IPlatform
        address targetExchangeAsset;
        /// @inheritdoc IPlatform
        address factory;
        /// @inheritdoc IPlatform
        address vaultManager;
        /// @inheritdoc IPlatform
        address strategyLogic;
        /// @inheritdoc IPlatform
        address priceReader;
        /// @inheritdoc IPlatform
        address aprOracle;
        /// @inheritdoc IPlatform
        address swapper;
        /// @inheritdoc IPlatform
        address hardWorker;
        /// @inheritdoc IPlatform
        address rebalancer;
        /// @inheritdoc IPlatform
        address zap;
        /// @inheritdoc IPlatform
        address bridge;
        /// @inheritdoc IPlatform
        string networkName;
        /// @inheritdoc IPlatform
        bytes32 networkExtra;
        /// @inheritdoc IPlatform
        uint minInitialBoostPerDay;
        /// @inheritdoc IPlatform
        uint minInitialBoostDuration;
        /// @inheritdoc IPlatform
        PlatformUpgrade pendingPlatformUpgrade;
        /// @inheritdoc IPlatform
        uint platformUpgradeTimelock;
        /// @inheritdoc IPlatform
        string platformVersion;
        /// @inheritdoc IPlatform
        uint minTvlForFreeHardWork;
        /// @inheritdoc IPlatform
        mapping(bytes32 ammAdapterIdHash => AmmAdapter ammAdpater) ammAdapter;
        /// @dev Hashes of AMM adapter ID string
        bytes32[] ammAdapterIdHash;
        EnumerableSet.AddressSet operators;
        EnumerableMap.AddressToUintMap allowedBBTokensVaults;
        EnumerableSet.AddressSet allowedBoostRewardTokens;
        EnumerableSet.AddressSet defaultBoostRewardTokens;
        EnumerableSet.AddressSet dexAggregators;
        uint fee;
        uint feeShareVaultManager;
        uint feeShareStrategyLogic;
        uint feeShareEcosystem;
        mapping(address vault => uint platformFee) customVaultFee;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(address multisig_, string memory version) public initializer {
        PlatformStorage storage $ = _getStorage();
        //slither-disable-next-line missing-zero-check
        $.multisig = multisig_;
        __Controllable_init(address(this));
        //slither-disable-next-line unused-return
        $.operators.add(msg.sender);
        //slither-disable-next-line unused-return
        $.operators.add(multisig_);
        $.platformVersion = version;
        emit PlatformVersion(version);
    }

    function setup(
        IPlatform.SetupAddresses memory addresses,
        IPlatform.PlatformSettings memory settings
    ) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        if ($.factory != address(0)) {
            revert AlreadyExist();
        }

        $.factory = addresses.factory;
        $.priceReader = addresses.priceReader;
        $.swapper = addresses.swapper;
        $.buildingPermitToken = addresses.buildingPermitToken;
        $.buildingPayPerVaultToken = addresses.buildingPayPerVaultToken;
        $.vaultManager = addresses.vaultManager;
        $.strategyLogic = addresses.strategyLogic;
        $.aprOracle = addresses.aprOracle;
        $.targetExchangeAsset = addresses.targetExchangeAsset;
        $.hardWorker = addresses.hardWorker;
        $.rebalancer = addresses.rebalancer;
        $.zap = addresses.zap;
        $.bridge = addresses.bridge;
        $.minTvlForFreeHardWork = 100e18;
        emit Addresses(
            $.multisig,
            addresses.factory,
            addresses.priceReader,
            addresses.swapper,
            addresses.buildingPermitToken,
            addresses.vaultManager,
            addresses.strategyLogic,
            addresses.aprOracle,
            addresses.hardWorker,
            addresses.rebalancer,
            addresses.zap,
            addresses.bridge
        );
        $.networkName = settings.networkName;
        $.networkExtra = settings.networkExtra;
        _setFees(
            settings.fee, settings.feeShareVaultManager, settings.feeShareStrategyLogic, settings.feeShareEcosystem
        );
        _setInitialBoost(settings.minInitialBoostPerDay, settings.minInitialBoostDuration);
        emit MinTvlForFreeHardWorkChanged(0, $.minTvlForFreeHardWork);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setEcosystemRevenueReceiver(address receiver) external onlyGovernanceOrMultisig {
        if (receiver == address(0)) {
            revert IControllable.IncorrectZeroArgument();
        }
        PlatformStorage storage $ = _getStorage();
        $.ecosystemRevenueReceiver = receiver;
        emit EcosystemRevenueReceiver(receiver);
    }

    /// @inheritdoc IPlatform
    function addOperator(address operator) external onlyGovernanceOrMultisig {
        PlatformStorage storage $ = _getStorage();
        if (!$.operators.add(operator)) {
            revert AlreadyExist();
        }
        emit OperatorAdded(operator);
    }

    /// @inheritdoc IPlatform
    function removeOperator(address operator) external onlyGovernanceOrMultisig {
        PlatformStorage storage $ = _getStorage();
        if (!$.operators.remove(operator)) {
            revert NotExist();
        }
        emit OperatorRemoved(operator);
    }

    /// @inheritdoc IPlatform
    function announcePlatformUpgrade(
        string memory newVersion,
        address[] memory proxies,
        address[] memory newImplementations
    ) external onlyGovernanceOrMultisig {
        PlatformStorage storage $ = _getStorage();
        if ($.pendingPlatformUpgrade.proxies.length != 0) {
            revert AlreadyAnnounced();
        }
        uint len = proxies.length;
        if (len != newImplementations.length) {
            revert IncorrectArrayLength();
        }
        // nosemgrep
        for (uint i; i < len; ++i) {
            if (proxies[i] == address(0)) {
                revert IControllable.IncorrectZeroArgument();
            }
            if (newImplementations[i] == address(0)) {
                revert IControllable.IncorrectZeroArgument();
            }
            //slither-disable-next-line calls-loop
            if (CommonLib.eq(IControllable(proxies[i]).VERSION(), IControllable(newImplementations[i]).VERSION())) {
                revert SameVersion();
            }
        }
        string memory oldVersion = $.platformVersion;
        if (CommonLib.eq(oldVersion, newVersion)) {
            revert SameVersion();
        }
        $.pendingPlatformUpgrade.newVersion = newVersion;
        $.pendingPlatformUpgrade.proxies = proxies;
        $.pendingPlatformUpgrade.newImplementations = newImplementations;
        uint tl = block.timestamp + TIME_LOCK;
        $.platformUpgradeTimelock = tl;
        emit UpgradeAnnounce(oldVersion, newVersion, proxies, newImplementations, tl);
    }

    /// @inheritdoc IPlatform
    //slither-disable-next-line reentrancy-benign reentrancy-no-eth calls-loop
    function upgrade() external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        uint ts = $.platformUpgradeTimelock;
        if (ts == 0) {
            revert NoNewVersion();
        }
        //slither-disable-next-line timestamp
        if (ts > block.timestamp) {
            revert UpgradeTimerIsNotOver(ts);
        }
        PlatformUpgrade memory platformUpgrade = $.pendingPlatformUpgrade;
        uint len = platformUpgrade.proxies.length;
        // nosemgrep
        for (uint i; i < len; ++i) {
            //slither-disable-next-line calls-loop
            string memory oldContractVersion = IControllable(platformUpgrade.proxies[i]).VERSION();
            //slither-disable-next-line calls-loop
            IProxy(platformUpgrade.proxies[i]).upgrade(platformUpgrade.newImplementations[i]);
            //slither-disable-next-line calls-loop reentrancy-events
            emit ProxyUpgraded(
                platformUpgrade.proxies[i],
                platformUpgrade.newImplementations[i],
                oldContractVersion,
                IControllable(platformUpgrade.proxies[i]).VERSION()
            );
        }
        $.platformVersion = platformUpgrade.newVersion;
        $.pendingPlatformUpgrade.newVersion = "";
        $.pendingPlatformUpgrade.proxies = new address[](0);
        $.pendingPlatformUpgrade.newImplementations = new address[](0);
        $.platformUpgradeTimelock = 0;
        //slither-disable-next-line reentrancy-events
        emit PlatformVersion(platformUpgrade.newVersion);
    }

    /// @inheritdoc IPlatform
    function cancelUpgrade() external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        if ($.platformUpgradeTimelock == 0) {
            revert NoNewVersion();
        }
        emit CancelUpgrade(VERSION, $.pendingPlatformUpgrade.newVersion);
        $.pendingPlatformUpgrade.newVersion = "";
        $.pendingPlatformUpgrade.proxies = new address[](0);
        $.pendingPlatformUpgrade.newImplementations = new address[](0);
        $.platformUpgradeTimelock = 0;
    }

    function setFees(
        uint fee,
        uint feeShareVaultManager,
        uint feeShareStrategyLogic,
        uint feeShareEcosystem
    ) external onlyGovernance {
        _setFees(fee, feeShareVaultManager, feeShareStrategyLogic, feeShareEcosystem);
    }

    /// @inheritdoc IPlatform
    function addAmmAdapter(string memory id, address proxy) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        bytes32 hash = keccak256(bytes(id));
        if ($.ammAdapter[hash].proxy != address(0)) {
            revert AlreadyExist();
        }
        $.ammAdapter[hash].id = id;
        $.ammAdapter[hash].proxy = proxy;
        $.ammAdapterIdHash.push(hash);
        emit NewAmmAdapter(id, proxy);
    }

    /// @inheritdoc IPlatform
    function addDexAggregators(address[] memory dexAggRouter) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        uint len = dexAggRouter.length;
        // nosemgrep
        for (uint i; i < len; ++i) {
            if (dexAggRouter[i] == address(0)) {
                revert IControllable.IncorrectZeroArgument();
            }
            // nosemgrep
            if (!$.dexAggregators.add(dexAggRouter[i])) {
                continue;
            }
            emit AddDexAggregator(dexAggRouter[i]);
        }
    }

    /// @inheritdoc IPlatform
    function removeDexAggregator(address dexAggRouter) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        if (!$.dexAggregators.remove(dexAggRouter)) {
            revert AggregatorNotExists(dexAggRouter);
        }
        emit RemoveDexAggregator(dexAggRouter);
    }

    /// @inheritdoc IPlatform
    function setAllowedBBTokenVaults(address bbToken, uint vaultsToBuild) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        bool firstSet = $.allowedBBTokensVaults.set(bbToken, vaultsToBuild);
        emit SetAllowedBBTokenVaults(bbToken, vaultsToBuild, firstSet);
    }

    /// @inheritdoc IPlatform
    function useAllowedBBTokenVault(address bbToken) external onlyFactory {
        PlatformStorage storage $ = _getStorage();
        uint allowedVaults = $.allowedBBTokensVaults.get(bbToken);
        if (allowedVaults <= 0) {
            revert NotEnoughAllowedBBToken();
        }
        //slither-disable-next-line unused-return
        $.allowedBBTokensVaults.set(bbToken, allowedVaults - 1);
        emit AllowedBBTokenVaultUsed(bbToken, allowedVaults - 1);
    }

    function removeAllowedBBToken(address bbToken) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        if (!$.allowedBBTokensVaults.remove(bbToken)) {
            revert NotExist();
        }
        emit RemoveAllowedBBToken(bbToken);
    }

    /// @inheritdoc IPlatform
    function addAllowedBoostRewardToken(address token) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        if (!$.allowedBoostRewardTokens.add(token)) {
            revert AlreadyExist();
        }
        emit AddAllowedBoostRewardToken(token);
    }

    /// @inheritdoc IPlatform
    function removeAllowedBoostRewardToken(address token) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        if (!$.allowedBoostRewardTokens.remove(token)) {
            revert NotExist();
        }
        emit RemoveAllowedBoostRewardToken(token);
    }

    /// @inheritdoc IPlatform
    function addDefaultBoostRewardToken(address token) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        if (!$.defaultBoostRewardTokens.add(token)) {
            revert AlreadyExist();
        }
        emit AddDefaultBoostRewardToken(token);
    }

    /// @inheritdoc IPlatform
    function removeDefaultBoostRewardToken(address token) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        if (!$.defaultBoostRewardTokens.remove(token)) {
            revert NotExist();
        }
        emit RemoveDefaultBoostRewardToken(token);
    }

    /// @inheritdoc IPlatform
    function addBoostTokens(
        address[] memory allowedBoostRewardToken,
        address[] memory defaultBoostRewardToken
    ) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        _addTokens($.allowedBoostRewardTokens, allowedBoostRewardToken);
        _addTokens($.defaultBoostRewardTokens, defaultBoostRewardToken);
        emit AddBoostTokens(allowedBoostRewardToken, defaultBoostRewardToken);
    }

    /// @inheritdoc IPlatform
    function setInitialBoost(uint minInitialBoostPerDay_, uint minInitialBoostDuration_) external onlyOperator {
        _setInitialBoost(minInitialBoostPerDay_, minInitialBoostDuration_);
    }

    /// @inheritdoc IPlatform
    function setMinTvlForFreeHardWork(uint value) external onlyGovernanceOrMultisig {
        PlatformStorage storage $ = _getStorage();
        emit MinTvlForFreeHardWorkChanged($.minTvlForFreeHardWork, value);
        $.minTvlForFreeHardWork = value;
    }

    /// @inheritdoc IPlatform
    function setCustomVaultFee(address vault, uint platformFee) external onlyGovernanceOrMultisig {
        PlatformStorage storage $ = _getStorage();
        emit CustomVaultFee(vault, platformFee);
        $.customVaultFee[vault] = platformFee;
    }

    /// @inheritdoc IPlatform
    function setupRebalancer(address rebalancer_) external onlyGovernanceOrMultisig {
        PlatformStorage storage $ = _getStorage();
        emit Rebalancer(rebalancer_);
        $.rebalancer = rebalancer_;
    }

    /// @inheritdoc IPlatform
    function setupBridge(address bridge_) external onlyGovernanceOrMultisig {
        PlatformStorage storage $ = _getStorage();
        emit Bridge(bridge_);
        $.bridge = bridge_;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IPlatform
    function pendingPlatformUpgrade() external view returns (PlatformUpgrade memory) {
        PlatformStorage storage $ = _getStorage();
        return $.pendingPlatformUpgrade;
    }

    /// @inheritdoc IPlatform
    function isOperator(address operator) external view returns (bool) {
        PlatformStorage storage $ = _getStorage();
        return $.operators.contains(operator);
    }

    function operatorsList() external view returns (address[] memory) {
        PlatformStorage storage $ = _getStorage();
        return $.operators.values();
    }

    /// @inheritdoc IPlatform
    function getFees()
        public
        view
        returns (uint fee, uint feeShareVaultManager, uint feeShareStrategyLogic, uint feeShareEcosystem)
    {
        PlatformStorage storage $ = _getStorage();
        return ($.fee, $.feeShareVaultManager, $.feeShareStrategyLogic, $.feeShareEcosystem);
    }

    /// @inheritdoc IPlatform
    function getCustomVaultFee(address vault) external view returns (uint fee) {
        PlatformStorage storage $ = _getStorage();
        return $.customVaultFee[vault];
    }

    /// @inheritdoc IPlatform
    function getPlatformSettings() external view returns (PlatformSettings memory) {
        PlatformStorage storage $ = _getStorage();
        //slither-disable-next-line uninitialized-local
        PlatformSettings memory platformSettings;
        (
            platformSettings.fee,
            platformSettings.feeShareVaultManager,
            platformSettings.feeShareStrategyLogic,
            platformSettings.feeShareEcosystem
        ) = getFees();
        platformSettings.networkName = $.networkName;
        platformSettings.networkExtra = $.networkExtra;
        platformSettings.minInitialBoostPerDay = $.minInitialBoostPerDay;
        platformSettings.minInitialBoostDuration = $.minInitialBoostDuration;
        return platformSettings;
    }

    /// @inheritdoc IPlatform
    function getAmmAdapters() external view returns (string[] memory ids, address[] memory proxies) {
        PlatformStorage storage $ = _getStorage();
        uint len = $.ammAdapterIdHash.length;
        ids = new string[](len);
        proxies = new address[](len);
        bytes32[] memory _ammAdapterIdHash = $.ammAdapterIdHash;
        // nosemgrep
        for (uint i; i < len; ++i) {
            bytes32 hash = _ammAdapterIdHash[i];
            AmmAdapter memory __ammAdapter = $.ammAdapter[hash];
            ids[i] = __ammAdapter.id;
            proxies[i] = __ammAdapter.proxy;
        }
    }

    /// @inheritdoc IPlatform
    function ammAdapter(bytes32 ammAdapterIdHash) external view returns (AmmAdapter memory) {
        PlatformStorage storage $ = _getStorage();
        return $.ammAdapter[ammAdapterIdHash];
    }

    /// @inheritdoc IPlatform
    function allowedBBTokens() external view returns (address[] memory) {
        PlatformStorage storage $ = _getStorage();
        return $.allowedBBTokensVaults.keys();
    }

    /// @inheritdoc IPlatform
    //slither-disable-next-line unused-return
    function allowedBBTokenVaults(address token) external view returns (uint vaultsLimit) {
        PlatformStorage storage $ = _getStorage();
        //slither-disable-next-line unused-return
        (, vaultsLimit) = $.allowedBBTokensVaults.tryGet(token);
    }

    /// @inheritdoc IPlatform
    function allowedBBTokenVaults() external view returns (address[] memory bbToken, uint[] memory vaultsLimit) {
        PlatformStorage storage $ = _getStorage();
        bbToken = $.allowedBBTokensVaults.keys();
        uint len = bbToken.length;
        vaultsLimit = new uint[](len);
        // nosemgrep
        for (uint i; i < len; ++i) {
            //slither-disable-next-line unused-return
            (, vaultsLimit[i]) = $.allowedBBTokensVaults.tryGet(bbToken[i]);
        }
    }

    /// @inheritdoc IPlatform
    function allowedBBTokenVaultsFiltered()
        external
        view
        returns (address[] memory bbToken, uint[] memory vaultsLimit)
    {
        PlatformStorage storage $ = _getStorage();
        address[] memory allBbTokens = $.allowedBBTokensVaults.keys();
        uint len = allBbTokens.length;
        uint[] memory limit = new uint[](len);
        //slither-disable-next-line uninitialized-local
        uint k;
        // nosemgrep
        for (uint i; i < len; ++i) {
            // nosemgrep
            limit[i] = $.allowedBBTokensVaults.get(allBbTokens[i]);
            if (limit[i] > 0) ++k;
        }
        bbToken = new address[](k);
        vaultsLimit = new uint[](k);
        //slither-disable-next-line uninitialized-local
        uint y;
        // nosemgrep
        for (uint i; i < len; ++i) {
            if (limit[i] == 0) {
                continue;
            }
            bbToken[y] = allBbTokens[i];
            vaultsLimit[y] = limit[i];
            ++y;
        }
    }

    /// @inheritdoc IPlatform
    function allowedBoostRewardTokens() external view returns (address[] memory) {
        PlatformStorage storage $ = _getStorage();
        return $.allowedBoostRewardTokens.values();
    }

    /// @inheritdoc IPlatform
    function defaultBoostRewardTokens() external view returns (address[] memory) {
        PlatformStorage storage $ = _getStorage();
        return $.defaultBoostRewardTokens.values();
    }

    /// @inheritdoc IPlatform
    function defaultBoostRewardTokensFiltered(address addressToRemove) external view returns (address[] memory) {
        PlatformStorage storage $ = _getStorage();
        return CommonLib.filterAddresses($.defaultBoostRewardTokens.values(), addressToRemove);
    }

    /// @inheritdoc IPlatform
    function dexAggregators() external view returns (address[] memory) {
        PlatformStorage storage $ = _getStorage();
        return $.dexAggregators.values();
    }

    /// @inheritdoc IPlatform
    function isAllowedDexAggregatorRouter(address dexAggRouter) external view returns (bool) {
        PlatformStorage storage $ = _getStorage();
        return $.dexAggregators.contains(dexAggRouter);
    }

    /// @inheritdoc IPlatform
    //slither-disable-next-line unused-return
    function getData()
        external
        view
        returns (
            address[] memory platformAddresses,
            address[] memory bcAssets,
            address[] memory dexAggregators_,
            string[] memory vaultType,
            bytes32[] memory vaultExtra,
            //slither-disable-next-line similar-names
            uint[] memory vaultBuildingPrice,
            string[] memory strategyId,
            bool[] memory isFarmingStrategy,
            string[] memory strategyTokenURI,
            bytes32[] memory strategyExtra
        )
    {
        PlatformStorage storage $ = _getStorage();
        address factory_ = $.factory;
        if (factory_ == address(0)) {
            revert NotExist();
        }

        platformAddresses = new address[](9);
        platformAddresses[0] = factory_;
        platformAddresses[1] = $.vaultManager;
        platformAddresses[2] = $.strategyLogic;
        platformAddresses[3] = $.buildingPermitToken;
        platformAddresses[4] = $.buildingPayPerVaultToken;
        platformAddresses[5] = $.governance;
        platformAddresses[6] = $.multisig;
        platformAddresses[7] = $.zap;
        platformAddresses[8] = $.bridge;

        ISwapper _swapper = ISwapper($.swapper);
        bcAssets = _swapper.bcAssets();
        dexAggregators_ = $.dexAggregators.values();
        IFactory _factory = IFactory(factory_);
        (vaultType,,,, vaultBuildingPrice, vaultExtra) = _factory.vaultTypes();
        (strategyId,,, isFarmingStrategy,, strategyTokenURI, strategyExtra) = _factory.strategies();
    }

    /// @inheritdoc IPlatform
    //slither-disable-next-line unused-return
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
        )
    {
        PlatformStorage storage $ = _getStorage();
        token = ISwapper($.swapper).allAssets();
        IPriceReader _priceReader = IPriceReader($.priceReader);
        uint len = token.length;
        tokenPrice = new uint[](len);
        tokenUserBalance = new uint[](len);
        // nosemgrep
        for (uint i; i < len; ++i) {
            //slither-disable-next-line calls-loop
            (tokenPrice[i],) = _priceReader.getPrice(token[i]);
            //slither-disable-next-line calls-loop
            tokenUserBalance[i] = IERC20(token[i]).balanceOf(yourAccount);
        }

        vault = IVaultManager($.vaultManager).vaultAddresses();
        len = vault.length;
        vaultSharePrice = new uint[](len);
        vaultUserBalance = new uint[](len);
        // nosemgrep
        for (uint i; i < len; ++i) {
            //slither-disable-next-line calls-loop unused-return
            (vaultSharePrice[i],) = IVault(vault[i]).price();
            //slither-disable-next-line calls-loop
            vaultUserBalance[i] = IERC20(vault[i]).balanceOf(yourAccount);
        }

        len = 3;
        nft = new address[](len);
        nft[0] = $.buildingPermitToken;
        nft[1] = $.vaultManager;
        nft[2] = $.strategyLogic;
        nftUserBalance = new uint[](len);
        // nosemgrep
        for (uint i; i < len; ++i) {
            //slither-disable-next-line calls-loop
            if (nft[i] != address(0)) {
                nftUserBalance[i] = IERC721(nft[i]).balanceOf(yourAccount);
            }
        }

        buildingPayPerVaultTokenBalance = IERC20($.buildingPayPerVaultToken).balanceOf(yourAccount);
    }

    /// @inheritdoc IPlatform
    function platformVersion() external view returns (string memory) {
        PlatformStorage storage $ = _getStorage();
        return $.platformVersion;
    }

    /// @inheritdoc IPlatform
    function governance() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.governance;
    }

    /// @inheritdoc IPlatform
    function multisig() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.multisig;
    }

    /// @inheritdoc IPlatform
    function buildingPayPerVaultToken() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.buildingPayPerVaultToken;
    }

    /// @inheritdoc IPlatform
    function buildingPermitToken() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.buildingPermitToken;
    }

    /// @inheritdoc IPlatform
    function ecosystemRevenueReceiver() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.ecosystemRevenueReceiver;
    }

    /// @inheritdoc IPlatform
    function targetExchangeAsset() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.targetExchangeAsset;
    }

    /// @inheritdoc IPlatform
    function factory() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.factory;
    }

    /// @inheritdoc IPlatform
    function vaultManager() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.vaultManager;
    }

    /// @inheritdoc IPlatform
    function strategyLogic() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.strategyLogic;
    }

    /// @inheritdoc IPlatform
    function priceReader() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.priceReader;
    }

    /// @inheritdoc IPlatform
    function aprOracle() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.aprOracle;
    }

    /// @inheritdoc IPlatform
    function swapper() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.swapper;
    }

    /// @inheritdoc IPlatform
    function hardWorker() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.hardWorker;
    }

    /// @inheritdoc IPlatform
    function rebalancer() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.rebalancer;
    }

    /// @inheritdoc IPlatform
    function zap() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.zap;
    }

    /// @inheritdoc IPlatform
    function bridge() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.bridge;
    }

    /// @inheritdoc IPlatform
    function minInitialBoostDuration() external view returns (uint) {
        PlatformStorage storage $ = _getStorage();
        return $.minInitialBoostDuration;
    }

    /// @inheritdoc IPlatform
    function minInitialBoostPerDay() external view returns (uint) {
        PlatformStorage storage $ = _getStorage();
        return $.minInitialBoostPerDay;
    }

    /// @inheritdoc IPlatform
    function networkExtra() external view returns (bytes32) {
        PlatformStorage storage $ = _getStorage();
        return $.networkExtra;
    }

    /// @inheritdoc IPlatform
    function networkName() external view returns (string memory) {
        PlatformStorage storage $ = _getStorage();
        return $.networkName;
    }

    /// @inheritdoc IPlatform
    function platformUpgradeTimelock() external view returns (uint) {
        PlatformStorage storage $ = _getStorage();
        return $.platformUpgradeTimelock;
    }

    /// @inheritdoc IPlatform
    function minTvlForFreeHardWork() external view returns (uint) {
        PlatformStorage storage $ = _getStorage();
        return $.minTvlForFreeHardWork;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _setFees(
        uint fee,
        uint feeShareVaultManager,
        uint feeShareStrategyLogic,
        uint feeShareEcosystem
    ) internal {
        PlatformStorage storage $ = _getStorage();
        address ecosystemRevenueReceiver_ = $.ecosystemRevenueReceiver;
        // nosemgrep
        if (feeShareEcosystem != 0 && ecosystemRevenueReceiver_ == address(0)) {
            revert IControllable.IncorrectZeroArgument();
            // revert IncorrectFee(0,0);
        }
        if (fee < MIN_FEE || fee > MAX_FEE) {
            revert IncorrectFee(MIN_FEE, MAX_FEE);
        }
        if (feeShareVaultManager < MIN_FEE_SHARE_VAULT_MANAGER) {
            revert IncorrectFee(MIN_FEE_SHARE_VAULT_MANAGER, 0);
        }
        if (feeShareStrategyLogic < MIN_FEE_SHARE_STRATEGY_LOGIC) {
            revert IncorrectFee(MIN_FEE_SHARE_STRATEGY_LOGIC, 0);
        }
        if (feeShareVaultManager + feeShareStrategyLogic + feeShareEcosystem > ConstantsLib.DENOMINATOR) {
            revert IncorrectFee(0, ConstantsLib.DENOMINATOR);
        }
        $.fee = fee;
        $.feeShareVaultManager = feeShareVaultManager;
        $.feeShareStrategyLogic = feeShareStrategyLogic;
        $.feeShareEcosystem = feeShareEcosystem;
        emit FeesChanged(fee, feeShareVaultManager, feeShareStrategyLogic, feeShareEcosystem);
    }

    function _setInitialBoost(uint minInitialBoostPerDay_, uint minInitialBoostDuration_) internal {
        PlatformStorage storage $ = _getStorage();
        $.minInitialBoostPerDay = minInitialBoostPerDay_;
        $.minInitialBoostDuration = minInitialBoostDuration_;
        emit MinInitialBoostChanged(minInitialBoostPerDay_, minInitialBoostDuration_);
    }

    /**
     * @dev Adds tokens to a specified token set.
     * @param tokenSet The target token set.
     * @param tokens Array of tokens to be added.
     */
    function _addTokens(EnumerableSet.AddressSet storage tokenSet, address[] memory tokens) internal {
        uint len = tokens.length;
        // nosemgrep
        for (uint i = 0; i < len; ++i) {
            if (!tokenSet.add(tokens[i])) {
                revert TokenAlreadyExistsInSet({token: tokens[i]});
            }
        }
    }

    function _getStorage() private pure returns (PlatformStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := PLATFORM_STORAGE_LOCATION
        }
    }
}
