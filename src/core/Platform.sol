// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

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
///         It stores core and infrastructure addresses, list of operators, fee settings and allows the governance to upgrade contracts.
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
contract Platform is Controllable, IPlatform {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    //region ----- Constants -----

    /// @dev Version of Platform contract implementation
    string public constant VERSION = '1.0.0';

    /// @inheritdoc IPlatform
    uint public constant TIME_LOCK = 16 hours;

    /// @dev Minimal revenue fee
    uint public constant MIN_FEE = 5_000; // 5%

    /// @dev Maximal revenue fee
    uint public constant MAX_FEE = 10_000; // 10%

    /// @dev Minimal VaultManager tokenId owner fee share
    uint public constant MIN_FEE_SHARE_VAULT_MANAGER = 10_000; // 10%

    /// @dev Minimal StrategyLogic tokenId owner fee share
    uint public constant MIN_FEE_SHARE_STRATEGY_LOGIC = 10_000; // 10%

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.Platform")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant PLATFORM_STORAGE_LOCATION = 0x263d5089de5bb3f97c8effd51f1a153b36e97065a51e67a94885830ed03a7a00;

    //endregion -- Constants -----

    //region ----- Storage -----

    /// @custom:storage-location erc7201:stability.Platform
    struct PlatformStorage {
        /// @inheritdoc IPlatform
        address governance;    
        /// @inheritdoc IPlatform
        address multisig;
        /// @inheritdoc IPlatform
        address vaultManager;
        /// @inheritdoc IPlatform
        address strategyLogic;
        /// @inheritdoc IPlatform
        address factory;
        /// @inheritdoc IPlatform
        address priceReader;
        /// @inheritdoc IPlatform
        address aprOracle;
        /// @inheritdoc IPlatform
        address swapper;
        /// @inheritdoc IPlatform
        address buildingPermitToken;
        /// @inheritdoc IPlatform
        address buildingPayPerVaultToken;
        /// @inheritdoc IPlatform
        address ecosystemRevenueReceiver;
        /// @inheritdoc IPlatform
        address hardWorker;
        /// @inheritdoc IPlatform
        address zap;
        /// @inheritdoc IPlatform
        address targetExchangeAsset;
        /// @inheritdoc IPlatform
        string networkName;
        /// @inheritdoc IPlatform
        bytes32 networkExtra;
        /// @inheritdoc IPlatform
        uint minInitialBoostPerDay;
        /// @inheritdoc IPlatform
        uint minInitialBoostDuration;
        PlatformUpgrade _pendingPlatformUpgrade;
        uint platformUpgradeTimelock;
        /// @inheritdoc IPlatform
        string PLATFORM_VERSION;
        mapping(bytes32 ammAdapterIdHash => AmmAdapter ammAdpater) _ammAdapter;
        /// @dev Hashes of AMM adapter ID string
        bytes32[] _ammAdapterIdHash;
        /// @dev 2 slots struct
        EnumerableSet.AddressSet _operators;
        /// @dev 3 slots structs
        EnumerableMap.AddressToUintMap _allowedBBTokensVaults;
        /// @dev 2 slots struct
        EnumerableSet.AddressSet _allowedBoostRewardTokens;
        /// @dev 2 slots struct
        EnumerableSet.AddressSet _defaultBoostRewardTokens;
        EnumerableSet.AddressSet _dexAggregators;
        uint _fee;
        uint _feeShareVaultManager;
        uint _feeShareStrategyLogic;
        uint _feeShareEcosystem;
    }

    //endregion -- Storage -----

    //region ----- Init -----

    function initialize(address multisig_, string memory version) public initializer {
        PlatformStorage storage $ = _getStorage();
        //slither-disable-next-line missing-zero-check
        $.multisig = multisig_;
        __Controllable_init(address(this));
        //slither-disable-next-line unused-return
        $._operators.add(msg.sender);
        $.PLATFORM_VERSION = version;
        emit PlatformVersion(version);
    }

    function setup(
        IPlatform.SetupAddresses memory addresses,
        IPlatform.PlatformSettings memory settings
    ) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        if($.factory != address(0)){
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
        $.zap = addresses.zap;
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
            addresses.zap
        );
        $.networkName = settings.networkName;
        $.networkExtra = settings.networkExtra;
        // _setFees(6_000, 30_000, 30_000, 0);
        _setFees(settings.fee, settings.feeShareVaultManager, settings.feeShareStrategyLogic, settings.feeShareEcosystem);
        _setInitialBoost(settings.minInitialBoostPerDay, settings.minInitialBoostDuration);
    }

    //endregion -- Init -----

    //region ----- Restricted actions -----

    function setEcosystemRevenueReceiver(address receiver) external onlyGovernanceOrMultisig {
        if(receiver == address(0)){
            revert IControllable.IncorrectZeroArgument();
        }
        PlatformStorage storage $ = _getStorage();
        $.ecosystemRevenueReceiver = receiver;
        emit EcosystemRevenueReceiver(receiver);
    }

    /// @inheritdoc IPlatform
    function addOperator(address operator) external onlyGovernanceOrMultisig {
        PlatformStorage storage $ = _getStorage();
        if(!$._operators.add(operator)){
            revert AlreadyExist();
        }
        emit OperatorAdded(operator);
    }

    /// @inheritdoc IPlatform
    function removeOperator(address operator) external onlyGovernanceOrMultisig {
        PlatformStorage storage $ = _getStorage();
        if(!$._operators.remove(operator)){
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
        if($._pendingPlatformUpgrade.proxies.length != 0){
            revert AlreadyAnnounced();
        }
        uint len = proxies.length;
        if(len != newImplementations.length){
            revert IncorrectArrayLength();
        }
        for (uint i; i < len; ++i) {
            if(proxies[i] == address(0)){
                revert IControllable.IncorrectZeroArgument();
            }
            if(newImplementations[i] == address(0)){
                revert IControllable.IncorrectZeroArgument();
            }
            if(CommonLib.eq(IControllable(proxies[i]).VERSION(), IControllable(newImplementations[i]).VERSION())){
                revert SameVersion();
            }
        }
        string memory oldVersion = $.PLATFORM_VERSION;
        if(CommonLib.eq(oldVersion, newVersion)){
            revert SameVersion();
        }
        $._pendingPlatformUpgrade.newVersion = newVersion;
        $._pendingPlatformUpgrade.proxies = proxies;
        $._pendingPlatformUpgrade.newImplementations = newImplementations;
        uint tl = block.timestamp + TIME_LOCK;
        $.platformUpgradeTimelock = tl;
        emit UpgradeAnnounce(oldVersion, newVersion, proxies, newImplementations, tl);
    }

    /// @inheritdoc IPlatform
    function upgrade() external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        uint ts = $.platformUpgradeTimelock;
        if(ts == 0){
            revert NoNewVersion();
        }
        if(ts > block.timestamp){
            revert UpgradeTimerIsNotOver(ts);
        }
        PlatformUpgrade memory platformUpgrade = $._pendingPlatformUpgrade;
        uint len = platformUpgrade.proxies.length;
        for (uint i; i < len; ++i) {
            string memory oldContractVersion = IControllable(platformUpgrade.proxies[i]).VERSION();
            IProxy(platformUpgrade.proxies[i]).upgrade(platformUpgrade.newImplementations[i]);
            emit ProxyUpgraded(
                platformUpgrade.proxies[i],
                platformUpgrade.newImplementations[i],
                oldContractVersion,
                IControllable(platformUpgrade.proxies[i]).VERSION()
            );
        }
        $.PLATFORM_VERSION = platformUpgrade.newVersion;
        $._pendingPlatformUpgrade.newVersion = '';
        $._pendingPlatformUpgrade.proxies = new address[](0);
        $._pendingPlatformUpgrade.newImplementations = new address[](0);
        $.platformUpgradeTimelock = 0;
        emit PlatformVersion(platformUpgrade.newVersion);
    }

    /// @inheritdoc IPlatform
    function cancelUpgrade() external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        if($.platformUpgradeTimelock == 0){
            revert NoNewVersion();
        }
        emit CancelUpgrade(VERSION, $._pendingPlatformUpgrade.newVersion);
        $._pendingPlatformUpgrade.newVersion = '';
        $._pendingPlatformUpgrade.proxies = new address[](0);
        $._pendingPlatformUpgrade.newImplementations = new address[](0);
        $.platformUpgradeTimelock = 0;
    }

    function setFees(uint fee, uint feeShareVaultManager, uint feeShareStrategyLogic, uint feeShareEcosystem) external onlyGovernance {
        _setFees(fee, feeShareVaultManager, feeShareStrategyLogic, feeShareEcosystem);
    }

    /// @inheritdoc IPlatform
    function addAmmAdapter(string memory id, address proxy) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        bytes32 hash = keccak256(bytes(id));
        if($._ammAdapter[hash].proxy != address(0)){
            revert AlreadyExist();
        }
        $._ammAdapter[hash].id = id;
        $._ammAdapter[hash].proxy = proxy;
        $._ammAdapterIdHash.push(hash);
        emit NewAmmAdapter(id, proxy);
    }

    /// @inheritdoc IPlatform
    function addDexAggregators(address[] memory dexAggRouter) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        uint len = dexAggRouter.length;
        for (uint i; i < len; ++i) {
            if (dexAggRouter[i] == address(0)) {
                revert IControllable.IncorrectZeroArgument();
            }
            //nosemgrep
            if (!$._dexAggregators.add(dexAggRouter[i])) {
                continue;
            }
            emit AddDexAggregator(dexAggRouter[i]);
        }
    }

    /// @inheritdoc IPlatform
    function removeDexAggregator(address dexAggRouter) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        if (!$._dexAggregators.remove(dexAggRouter)) {
            revert AggregatorNotExists(dexAggRouter);
        }
        emit RemoveDexAggregator(dexAggRouter);
    }

    /// @inheritdoc IPlatform
    function setAllowedBBTokenVaults(address bbToken, uint vaultsToBuild) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        bool firstSet = $._allowedBBTokensVaults.set(bbToken, vaultsToBuild);
        emit SetAllowedBBTokenVaults(bbToken, vaultsToBuild, firstSet);
    }

    /// @inheritdoc IPlatform
    function useAllowedBBTokenVault(address bbToken) external onlyFactory {
        PlatformStorage storage $ = _getStorage();
        uint allowedVaults = $._allowedBBTokensVaults.get(bbToken);
        if(allowedVaults <= 0){
            revert NotEnoughAllowedBBToken();
        }
        //slither-disable-next-line unused-return
        $._allowedBBTokensVaults.set(bbToken, allowedVaults - 1);
        emit AllowedBBTokenVaultUsed(bbToken, allowedVaults - 1);
    }

    function removeAllowedBBToken(address bbToken) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        if(!$._allowedBBTokensVaults.remove(bbToken)){
            revert NotExist();
        }
        emit RemoveAllowedBBToken(bbToken);
    }

    /// @inheritdoc IPlatform
    function addAllowedBoostRewardToken(address token) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        if(!$._allowedBoostRewardTokens.add(token)){
            revert AlreadyExist();
        }
        emit AddAllowedBoostRewardToken(token);
    }

    /// @inheritdoc IPlatform
    function removeAllowedBoostRewardToken(address token) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        if(!$._allowedBoostRewardTokens.remove(token)){
            revert NotExist();
        }
        emit RemoveAllowedBoostRewardToken(token);
    }

    /// @inheritdoc IPlatform
    function addDefaultBoostRewardToken(address token) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        if(!$._defaultBoostRewardTokens.add(token)){
            revert AlreadyExist();
        }
        emit AddDefaultBoostRewardToken(token);
    }

    /// @inheritdoc IPlatform
    function removeDefaultBoostRewardToken(address token) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        if(!$._defaultBoostRewardTokens.remove(token)){
            revert NotExist();
        }
        emit RemoveDefaultBoostRewardToken(token);
    }

    /// @inheritdoc IPlatform
    function addBoostTokens(address[] memory allowedBoostRewardToken, address[] memory defaultBoostRewardToken) external onlyOperator {
        PlatformStorage storage $ = _getStorage();
        _addTokens($._allowedBoostRewardTokens, allowedBoostRewardToken);
        _addTokens($._defaultBoostRewardTokens, defaultBoostRewardToken);
        emit AddBoostTokens(allowedBoostRewardToken, defaultBoostRewardToken);
    }

    //endregion -- Restricted actions ----

    //region ----- View functions -----

    /// @inheritdoc IPlatform
    function pendingPlatformUpgrade() external view returns (PlatformUpgrade memory) {
        PlatformStorage storage $ = _getStorage();
        return $._pendingPlatformUpgrade;
    }

    /// @inheritdoc IPlatform
    function isOperator(address operator) external view returns (bool) {
        PlatformStorage storage $ = _getStorage();
        return $._operators.contains(operator);
    }

    function operatorsList() external view returns (address[] memory) {
        PlatformStorage storage $ = _getStorage();
        return $._operators.values();
    }

    /// @inheritdoc IPlatform
    function getFees() public view returns (uint fee, uint feeShareVaultManager, uint feeShareStrategyLogic, uint feeShareEcosystem) {
        PlatformStorage storage $ = _getStorage();
        return ($._fee, $._feeShareVaultManager, $._feeShareStrategyLogic, $._feeShareEcosystem);
    }

    /// @inheritdoc IPlatform
    function getPlatformSettings() external view returns (PlatformSettings memory) {
        PlatformStorage storage $ = _getStorage();
        PlatformSettings memory platformSettings;
        (platformSettings.fee,platformSettings.feeShareVaultManager,platformSettings.feeShareStrategyLogic,platformSettings.feeShareEcosystem) = getFees();
        platformSettings.networkName = $.networkName;
        platformSettings.networkExtra = $.networkExtra;
        platformSettings.minInitialBoostPerDay = $.minInitialBoostPerDay;
        platformSettings.minInitialBoostDuration = $.minInitialBoostDuration;
        return platformSettings;
    }

    /// @inheritdoc IPlatform
    function getAmmAdapters() external view returns(string[] memory ids, address[] memory proxies) {
        PlatformStorage storage $ = _getStorage();
        uint len = $._ammAdapterIdHash.length;
        ids = new string[](len);
        proxies = new address[](len);
        for (uint i; i < len; ++i) {
            bytes32 hash = $._ammAdapterIdHash[i];
            AmmAdapter memory __ammAdapter = $._ammAdapter[hash];
            ids[i] = __ammAdapter.id;
            proxies[i] = __ammAdapter.proxy;
        }
    }

    /// @inheritdoc IPlatform
    function ammAdapter(bytes32 ammAdapterIdHash) external view returns(AmmAdapter memory) {
        PlatformStorage storage $ = _getStorage();
        return $._ammAdapter[ammAdapterIdHash];
    }

    /// @inheritdoc IPlatform
    function allowedBBTokens() external view returns(address[] memory) {
        PlatformStorage storage $ = _getStorage();
        return $._allowedBBTokensVaults.keys();
    }

    /// @inheritdoc IPlatform
    function allowedBBTokenVaults(address token) external view returns (uint vaultsLimit) {
        PlatformStorage storage $ = _getStorage();
        //slither-disable-next-line unused-return
        (, vaultsLimit) = $._allowedBBTokensVaults.tryGet(token);
    }

    /// @inheritdoc IPlatform
    function allowedBBTokenVaults() external view returns (address[] memory bbToken, uint[] memory vaultsLimit) {
        PlatformStorage storage $ = _getStorage();
        bbToken = $._allowedBBTokensVaults.keys();
        uint len = bbToken.length;
        vaultsLimit = new uint[](len);
        for (uint i; i < len; ++i) {
            (, vaultsLimit[i]) = $._allowedBBTokensVaults.tryGet(bbToken[i]);
        }
    }

    /// @inheritdoc IPlatform
    function allowedBBTokenVaultsFiltered() external view returns (address[] memory bbToken, uint[] memory vaultsLimit) {
        PlatformStorage storage $ = _getStorage();
        address[] memory allBbTokens = $._allowedBBTokensVaults.keys();
        uint len = allBbTokens.length;
        uint[] memory limit = new uint[](len);
        //slither-disable-next-line uninitialized-local
        uint k;
        for (uint i; i < len; ++i) {
            //nosemgrep
            limit[i] = $._allowedBBTokensVaults.get(allBbTokens[i]);
            if(limit[i] > 0) ++k;
        }
        bbToken = new address[](k);
        vaultsLimit = new uint[](k);
        //slither-disable-next-line uninitialized-local
        uint y;
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
    function allowedBoostRewardTokens() external view returns(address[] memory) {
        PlatformStorage storage $ = _getStorage();
        return $._allowedBoostRewardTokens.values();
    }

    /// @inheritdoc IPlatform
    function defaultBoostRewardTokens() external view returns(address[] memory) {
        PlatformStorage storage $ = _getStorage();
        return $._defaultBoostRewardTokens.values();
    }

    /// @inheritdoc IPlatform
    function defaultBoostRewardTokensFiltered(address addressToRemove) external view returns(address[] memory) {
        PlatformStorage storage $ = _getStorage();
        return CommonLib.filterAddresses($._defaultBoostRewardTokens.values(), addressToRemove);
    }

    /// @inheritdoc IPlatform
    function dexAggregators() external view returns(address[] memory) {
        PlatformStorage storage $ = _getStorage();
        return $._dexAggregators.values();
    }

    /// @inheritdoc IPlatform
    function isAllowedDexAggregatorRouter(address dexAggRouter) external view returns(bool) {
        PlatformStorage storage $ = _getStorage();
        return $._dexAggregators.contains(dexAggRouter);
    }

    /// @inheritdoc IPlatform
    function getData() external view returns(
        address[] memory platformAddresses,
        address[] memory bcAssets,
        address[] memory dexAggregators_,
        string[] memory vaultType,
        bytes32[] memory vaultExtra,
        uint[] memory vaultBuildingPrice,
        string[] memory strategyId,
        bool[] memory isFarmingStrategy,
        string[] memory strategyTokenURI,
        bytes32[] memory strategyExtra
    ) { 
        PlatformStorage storage $ = _getStorage();
        if($.factory == address(0)){
            revert NotExist();
        }
        
        platformAddresses = new address[](5);
        platformAddresses[0] = $.factory;
        platformAddresses[1] = $.vaultManager;
        platformAddresses[2] = $.strategyLogic;
        platformAddresses[3] = $.buildingPermitToken;
        platformAddresses[4] = $.buildingPayPerVaultToken;
        ISwapper _swapper = ISwapper($.swapper);
        bcAssets = _swapper.bcAssets();
        dexAggregators_ = $._dexAggregators.values();
        IFactory _factory = IFactory($.factory);
        (vaultType,,,,vaultBuildingPrice,vaultExtra) = _factory.vaultTypes();
        (strategyId,,,isFarmingStrategy,,strategyTokenURI,strategyExtra) = _factory.strategies();
    }

    /// @inheritdoc IPlatform
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
    ) {
        PlatformStorage storage $ = _getStorage();
        token = ISwapper($.swapper).allAssets();
        IPriceReader _priceReader = IPriceReader($.priceReader);
        uint len = token.length;
        tokenPrice = new uint[](len);
        tokenUserBalance = new uint[](len);
        for (uint i; i < len; ++i) {
            //slither-disable-next-line unused-return
            (tokenPrice[i],) = _priceReader.getPrice(token[i]);
            tokenUserBalance[i] = IERC20(token[i]).balanceOf(yourAccount);
        }

        vault = IVaultManager($.vaultManager).vaultAddresses();
        len = vault.length;
        vaultSharePrice = new uint[](len);
        vaultUserBalance = new uint[](len);
        for (uint i; i < len; ++i) {
            //slither-disable-next-line unused-return
            (vaultSharePrice[i],) = IVault(vault[i]).price();
            vaultUserBalance[i] = IERC20(vault[i]).balanceOf(yourAccount);
        }

        len = 3;
        nft = new address[](len);
        nft[0] = $.buildingPermitToken;
        nft[1] = $.vaultManager;
        nft[2] = $.strategyLogic;
        nftUserBalance = new uint[](len);
        for (uint i; i < len; ++i) {
            nftUserBalance[i] = IERC721(nft[i]).balanceOf(yourAccount);
        }

        buildingPayPerVaultTokenBalance = IERC20($.buildingPayPerVaultToken).balanceOf(yourAccount);
    }

    /// @inheritdoc IPlatform
    //slither-disable-next-line naming-convention
    function PLATFORM_VERSION() external view returns (string memory) {
        PlatformStorage storage $ = _getStorage();
        return $.PLATFORM_VERSION;
    }

    /// @inheritdoc IPlatform
    function aprOracle() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.aprOracle;
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
    function factory() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.factory;
    }

    /// @inheritdoc IPlatform
    function governance() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.governance;
    }

    /// @inheritdoc IPlatform
    function hardWorker() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.hardWorker;
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
    function multisig() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.multisig;
    }

    /// @inheritdoc IPlatform
    function priceReader() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.priceReader;
    }

    /// @inheritdoc IPlatform
    function strategyLogic() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.strategyLogic;
    }

    /// @inheritdoc IPlatform
    function swapper() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.swapper;
    }

    /// @inheritdoc IPlatform
    function targetExchangeAsset() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.targetExchangeAsset;
    }

    /// @inheritdoc IPlatform
    function vaultManager() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.vaultManager;
    }

    /// @inheritdoc IPlatform
    function zap() external view returns (address) {
        PlatformStorage storage $ = _getStorage();
        return $.zap;
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

    //endregion -- View functions -----

    //region ----- Internal logic -----

    function _setFees(uint fee, uint feeShareVaultManager, uint feeShareStrategyLogic, uint feeShareEcosystem) internal {
        PlatformStorage storage $ = _getStorage();
        if(feeShareEcosystem != 0 && $.ecosystemRevenueReceiver == address(0)){
            if($.ecosystemRevenueReceiver == address(0)){
                revert IControllable.IncorrectZeroArgument();
            } else {
                revert IncorrectFee(0,0);
            }
        } 
        if(fee < MIN_FEE || fee > MAX_FEE){
             revert IncorrectFee(MIN_FEE, MAX_FEE);
        } 
        if(feeShareVaultManager < MIN_FEE_SHARE_VAULT_MANAGER){
             revert IncorrectFee(MIN_FEE_SHARE_VAULT_MANAGER, 0);
        } 
        if(feeShareStrategyLogic < MIN_FEE_SHARE_STRATEGY_LOGIC){
             revert IncorrectFee(MIN_FEE_SHARE_STRATEGY_LOGIC, 0);
        } 
        if(feeShareVaultManager + feeShareStrategyLogic + feeShareEcosystem > ConstantsLib.DENOMINATOR){
             revert IncorrectFee(0, ConstantsLib.DENOMINATOR);
        } 
        $._fee = fee;
        $._feeShareVaultManager = feeShareVaultManager;
        $._feeShareStrategyLogic = feeShareStrategyLogic;
        $._feeShareEcosystem = feeShareEcosystem;
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

    //endregion -- Internal logic -----
}
