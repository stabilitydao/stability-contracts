// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Controllable} from "./base/Controllable.sol";
import {CommonLib} from "./libs/CommonLib.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IProxy} from "../interfaces/IProxy.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";

/// @notice The main contract of the platform.
///         It stores core and infrastructure addresses, list of operators, fee settings, allows platform upgrades etc.
///         ┏┓┏┳┓┏┓┳┓┳┓ ┳┏┳┓┓┏  ┏┓┓ ┏┓┏┳┓┏┓┏┓┳┓┳┳┓
///         ┗┓ ┃ ┣┫┣┫┃┃ ┃ ┃ ┗┫  ┃┃┃ ┣┫ ┃ ┣ ┃┃┣┫┃┃┃
///         ┗┛ ┻ ┛┗┻┛┻┗┛┻ ┻ ┗┛  ┣┛┗┛┛┗ ┻ ┻ ┗┛┛┗┛ ┗
/// Changelog:
///   1.6.1: IPlatform.recovery()
///   1.6.0: remove buildingPermitToken, buildingPayPerVaultToken, BB and boost related; init with MetaVaultFactory;
///   1.5.1: IPlatform.vaultPriceOracle()
///   1.5.0: remove feeShareVaultManager, feeShareStrategyLogic, feeShareEcosystem, networkName,
///          networkExtra, aprOracle
///   1.4.0: IPlatform.metaVaultFactory()
///   1.3.0: initialize fix for revenueRouter, cleanup bridge()
///   1.2.0: IPlatform.revenueRouter(), refactoring 0.8.28
///   1.1.0: custom vault fee
///   1.0.1: can work without buildingPermitToken
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
/// @author 0xhokugava (https://github.com/0xhokugava)
/// @author ruby (https://github.com/alexandersazonof)
contract Platform is Controllable, IPlatform {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of Platform contract implementation
    string public constant VERSION = "1.6.1";

    /// @inheritdoc IPlatform
    uint public constant TIME_LOCK = 16 hours;

    /// @dev Minimal revenue fee
    uint public constant MIN_FEE = 5_000; // 5%

    /// @dev Maximal revenue fee
    uint public constant MAX_FEE = 50_000; // 50%

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
        address __deprecated1;
        address __deprecated2;
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
        address __deprecated3;
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
        string __deprecated4;
        bytes32 __deprecated5;
        uint __deprecated6;
        uint __deprecated7;
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
        EnumerableMap.AddressToUintMap __deprecated8;
        EnumerableSet.AddressSet __deprecated9;
        EnumerableSet.AddressSet __deprecated10;
        EnumerableSet.AddressSet dexAggregators;
        uint fee;
        uint __deprecated11;
        uint __deprecated12;
        uint __deprecated13;
        mapping(address vault => uint platformFee) customVaultFee;
        /// @inheritdoc IPlatform
        address revenueRouter;
        /// @inheritdoc IPlatform
        address metaVaultFactory;
        /// @inheritdoc IPlatform
        address vaultPriceOracle;
        /// @inheritdoc IPlatform
        address recovery;
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
        require($.factory == address(0), AlreadyExist());

        $.factory = addresses.factory;
        $.priceReader = addresses.priceReader;
        $.swapper = addresses.swapper;
        $.vaultManager = addresses.vaultManager;
        $.strategyLogic = addresses.strategyLogic;
        $.targetExchangeAsset = addresses.targetExchangeAsset;
        $.hardWorker = addresses.hardWorker;
        $.zap = addresses.zap;
        $.revenueRouter = addresses.revenueRouter;
        $.metaVaultFactory = addresses.metaVaultFactory;
        $.vaultPriceOracle = addresses.vaultPriceOracle;
        // $.recovery is not set by default, use setupRecovery if needed
        $.minTvlForFreeHardWork = 100e18;
        emit Addresses(
            $.multisig,
            addresses.factory,
            addresses.priceReader,
            addresses.swapper,
            address(0),
            addresses.vaultManager,
            addresses.strategyLogic,
            address(0),
            addresses.hardWorker,
            address(0),
            addresses.zap,
            address(0)
        );
        emit RevenueRouter(addresses.revenueRouter);
        emit MetaVaultFactory(addresses.metaVaultFactory);
        _setFees(settings.fee);
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
        require($.operators.add(operator), AlreadyExist());
        emit OperatorAdded(operator);
    }

    /// @inheritdoc IPlatform
    function removeOperator(address operator) external onlyGovernanceOrMultisig {
        PlatformStorage storage $ = _getStorage();
        require($.operators.remove(operator), NotExist());
        emit OperatorRemoved(operator);
    }

    /// @inheritdoc IPlatform
    function announcePlatformUpgrade(
        string memory newVersion,
        address[] memory proxies,
        address[] memory newImplementations
    ) external onlyGovernanceOrMultisig {
        PlatformStorage storage $ = _getStorage();
        require($.pendingPlatformUpgrade.proxies.length == 0, AlreadyAnnounced());
        uint len = proxies.length;
        require(len == newImplementations.length, IncorrectArrayLength());

        for (uint i; i < len; ++i) {
            require(proxies[i] != address(0), IControllable.IncorrectZeroArgument());
            require(newImplementations[i] != address(0), IControllable.IncorrectZeroArgument());
            //slither-disable-next-line calls-loop
            require(
                !CommonLib.eq(IControllable(proxies[i]).VERSION(), IControllable(newImplementations[i]).VERSION()),
                SameVersion()
            );
        }
        string memory oldVersion = $.platformVersion;
        require(!CommonLib.eq(oldVersion, newVersion), SameVersion());
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
        require(ts != 0, NoNewVersion());
        //slither-disable-next-line timestamp
        require(block.timestamp > ts, UpgradeTimerIsNotOver(ts));
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
        require($.platformUpgradeTimelock != 0, NoNewVersion());
        emit CancelUpgrade(VERSION, $.pendingPlatformUpgrade.newVersion);
        $.pendingPlatformUpgrade.newVersion = "";
        $.pendingPlatformUpgrade.proxies = new address[](0);
        $.pendingPlatformUpgrade.newImplementations = new address[](0);
        $.platformUpgradeTimelock = 0;
    }

    function setFees(uint fee) external onlyGovernanceOrMultisig {
        _setFees(fee);
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

    function setupRevenueRouter(address revenueRouter_) external onlyGovernanceOrMultisig {
        PlatformStorage storage $ = _getStorage();
        emit RevenueRouter(revenueRouter_);
        $.revenueRouter = revenueRouter_;
    }

    function setupMetaVaultFactory(address metaVaultFactory_) external onlyGovernanceOrMultisig {
        PlatformStorage storage $ = _getStorage();
        emit MetaVaultFactory(metaVaultFactory_);
        $.metaVaultFactory = metaVaultFactory_;
    }

    /// @inheritdoc IPlatform
    function setupVaultPriceOracle(address vaultPriceOracle_) external onlyGovernanceOrMultisig {
        PlatformStorage storage $ = _getStorage();
        emit VaultPriceOracle(vaultPriceOracle_);
        $.vaultPriceOracle = vaultPriceOracle_;
    }

    /// @inheritdoc IPlatform
    function setupRecovery(address recovery_) external onlyGovernanceOrMultisig {
        PlatformStorage storage $ = _getStorage();
        emit Recovery(recovery_);
        $.recovery = recovery_;
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
    function getFees() public view returns (uint fee, uint, uint, uint) {
        PlatformStorage storage $ = _getStorage();
        return ($.fee, 0, 0, 0);
    }

    /// @inheritdoc IPlatform
    function getCustomVaultFee(address vault) external view returns (uint fee) {
        PlatformStorage storage $ = _getStorage();
        return $.customVaultFee[vault];
    }

    /// @inheritdoc IPlatform
    function getPlatformSettings() external view returns (PlatformSettings memory) {
        //slither-disable-next-line uninitialized-local
        PlatformSettings memory platformSettings;
        (platformSettings.fee,,,) = getFees();
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
        platformAddresses[3] = address(0);
        platformAddresses[4] = address(0);
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
    function revenueRouter() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.revenueRouter;
    }

    /// @inheritdoc IPlatform
    function metaVaultFactory() external view returns (address) {
        return _getStorage().metaVaultFactory;
    }

    /// @inheritdoc IPlatform
    function vaultPriceOracle() external view returns (address) {
        return _getStorage().vaultPriceOracle;
    }

    /// @inheritdoc IPlatform
    function recovery() external view returns (address) {
        return _getStorage().recovery;
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

    function _setFees(uint fee) internal {
        PlatformStorage storage $ = _getStorage();
        if (fee < MIN_FEE || fee > MAX_FEE) {
            revert IncorrectFee(MIN_FEE, MAX_FEE);
        }
        $.fee = fee;
        emit FeesChanged(fee, 0, 0, 0);
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
