// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./base/Controllable.sol";
import "./libs/CommonLib.sol";
import "./libs/VaultTypeLib.sol";
import "./libs/FactoryLib.sol";
import "./libs/DeployerLib.sol";
import "./libs/VaultStatusLib.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IVaultProxy.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyProxy.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/IStrategyLogic.sol";

/// @notice Platform factory assembling vaults. Stores vault settings, strategy logic, farms.
///         Provides the opportunity to upgrade vaults and strategies.
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
contract Factory is Controllable, ReentrancyGuardUpgradeable, IFactory {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    //region ----- Constants -----

    /// @inheritdoc IControllable
    string public constant VERSION = '1.0.0';

    uint internal constant _WEEK = 60 * 60 * 24 * 7;

    uint internal constant _PERMIT_PER_WEEK = 1;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.Factory")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant FACTORY_STORAGE_LOCATION = 0x94b53192a2415b53b438d03f0efa946204c0118192627e3d5ed4ba034c9a0300;

    //endregion -- Constants -----

    //region ----- Storage -----

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
    }

    //endregion -- Storage -----

    //region ----- Data types -----

    struct DeployVaultAndStrategyVars {
        VaultConfig vaultConfig;
        bytes32 strategyIdHash;
        address platform;
        address[] assets;
        string[] assetsSymbols;
        string name;
        string specificName;
        string symbol;
        bytes32 deploymentKey;
        address buildingPermitToken;
        address buildingPayPerVaultToken;
        bool permit;
        uint vaultManagerTokenId;
    }

    //endregion -- Data types -----

    //region ----- Init -----

    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
        __ReentrancyGuard_init();
    }

    //endregion -- Init -----

    //region ----- Restricted actions -----

    /// @inheritdoc IFactory
    function setVaultConfig(VaultConfig memory vaultConfig_) external onlyOperator {
        FactoryStorage storage $ = _getStorage();
        string memory type_ = vaultConfig_.vaultType;
        bytes32 typeHash = keccak256(abi.encodePacked(type_));
        $.vaultConfig[typeHash] = vaultConfig_;
        bool newVaultType = $.vaultTypeHashes.add(typeHash);
        emit VaultConfigChanged(type_, vaultConfig_.implementation, vaultConfig_.deployAllowed, vaultConfig_.upgradeAllowed, newVaultType);
    }

    /// @inheritdoc IFactory
    function setStrategyLogicConfig(StrategyLogicConfig memory config, address developer) external onlyOperator nonReentrant {
        FactoryStorage storage $ = _getStorage();
        bytes32 strategyIdHash = keccak256(bytes(config.id));
        StrategyLogicConfig storage oldConfig = $.strategyLogicConfig[strategyIdHash];
        if (oldConfig.implementation == address(0)) {
            uint tokenId = IStrategyLogic(IPlatform(platform()).strategyLogic()).mint(developer, config.id);
            config.tokenId = tokenId;
        } else {
            config.tokenId = oldConfig.tokenId;
        }
        $.strategyLogicConfig[strategyIdHash] = config;
        bool newStrategy = $.strategyLogicIdHashes.add(strategyIdHash);
        emit StrategyLogicConfigChanged(config.id, config.implementation, config.deployAllowed, config.upgradeAllowed, newStrategy);
    }

    /// @inheritdoc IFactory
    function setVaultStatus(address vault, uint status) external onlyGovernanceOrMultisig {
        FactoryStorage storage $ = _getStorage();
        $.vaultStatus[vault] = status;
        emit VaultStatus(vault, status);
    }

    /// @inheritdoc IFactory
    function addFarms(Farm[] memory farms_) external onlyOperator {
        FactoryStorage storage $ = _getStorage();
        uint len = farms_.length;
        //nosemgrep
        for (uint i = 0; i < len; ++i) {
            $.farms.push(farms_[i]);
        }
        emit NewFarm(farms_);
    }

    /// @inheritdoc IFactory
    function updateFarm(uint id, Farm memory farm_) external onlyOperator {
        FactoryStorage storage $ = _getStorage();
        $.farms[id] = farm_;
        emit UpdateFarm(id, farm_);
    }

    //endregion -- Restricted actions ----

    //region ----- User actions -----

    /// @inheritdoc IFactory
    function deployVaultAndStrategy(
        string memory vaultType,
        string memory strategyId,
        address[] memory vaultInitAddresses,
        uint[] memory vaultInitNums,
        address[] memory strategyInitAddresses,
        uint[] memory strategyInitNums,
        int24[] memory strategyInitTicks
    ) external nonReentrant returns (address vault, address strategy) {
        FactoryStorage storage $ = _getStorage();
        DeployVaultAndStrategyVars memory vars;
        vars.vaultConfig = $.vaultConfig[keccak256(abi.encodePacked(vaultType))];
        if(vars.vaultConfig.implementation == address(0)){
            revert VaultImplementationIsNotAvailable();
        }
        if(!vars.vaultConfig.deployAllowed){
            revert VaultNotAllowedToDeploy();
        }
        vars.strategyIdHash = keccak256(bytes(strategyId));
        vars.platform = platform();
        vars.buildingPermitToken = IPlatform(vars.platform).buildingPermitToken();
        vars.buildingPayPerVaultToken = IPlatform(vars.platform).buildingPayPerVaultToken();

        StrategyLogicConfig storage config = $.strategyLogicConfig[vars.strategyIdHash];
        if(config.implementation == address(0)){
            revert StrategyImplementationIsNotAvailable();
        }
        if(!config.deployAllowed){
            revert StrategyLogicNotAllowedToDeploy();
        }

        if (vars.buildingPermitToken != address(0)) {
            uint balance = IERC721Enumerable(vars.buildingPermitToken).balanceOf(msg.sender);
            for (uint i; i < balance; ++i) {
                uint tokenId = IERC721Enumerable(vars.buildingPermitToken).tokenOfOwnerByIndex(msg.sender, i);
                uint epoch = block.timestamp / _WEEK;
                uint builtThisWeek = $.vaultsBuiltByPermitTokenId[epoch][tokenId];
                if (builtThisWeek < _PERMIT_PER_WEEK) {
                    $.vaultsBuiltByPermitTokenId[epoch][tokenId] = builtThisWeek + 1;
                    vars.permit = true;
                    break;
                }
            }
        }

        if (!vars.permit) {
            uint userBalance = IERC20(vars.buildingPayPerVaultToken).balanceOf(msg.sender);
            if(userBalance < vars.vaultConfig.buildingPrice){
                revert YouDontHaveEnoughTokens
                    (
                    userBalance, 
                    vars.vaultConfig.buildingPrice, 
                    IPlatform(vars.platform).buildingPayPerVaultToken()
                    );
            }
            IERC20(vars.buildingPayPerVaultToken).safeTransferFrom(msg.sender, IPlatform(vars.platform).multisig(), vars.vaultConfig.buildingPrice);
        }

        {
            IVaultProxy vaultProxy = IVaultProxy(DeployerLib.deployVaultProxy());
            vaultProxy.initProxy(vaultType);
            IStrategyProxy strategyProxy = IStrategyProxy(DeployerLib.deployStrategyProxy());
            strategyProxy.initStrategyProxy(strategyId);
            vault = address(vaultProxy);
            strategy = address(strategyProxy);
        }

        {
            uint addressesLength = strategyInitAddresses.length;
            address[] memory initStrategyAddresses = new address[](2 + addressesLength);
            initStrategyAddresses[0] = vars.platform;
            initStrategyAddresses[1] = vault;
            for (uint i = 2; i < 2 + addressesLength; ++i) {
                initStrategyAddresses[i] = strategyInitAddresses[i - 2];
            }

            IStrategy(strategy).initialize(initStrategyAddresses, strategyInitNums, strategyInitTicks);

            // 3 addresses for not using exchangeAsset and other addresses in unique deployment key
            vars.deploymentKey = getDeploymentKey(
                vaultType,
                strategyId,
                vaultInitAddresses,
                vaultInitNums,
                strategyInitAddresses,
                strategyInitNums,
                strategyInitTicks
            );
            if($.deploymentKey[vars.deploymentKey] != address(0)){
                revert SuchVaultAlreadyDeployed(vars.deploymentKey);
            }
        }

        (,vars.assets, vars.assetsSymbols, vars.specificName, vars.symbol) = getStrategyData(vaultType, strategy, vaultInitAddresses.length > 0 ? vaultInitAddresses[0] : address(0));
        vars.name = FactoryLib.getName(vaultType, strategyId, CommonLib.implode(vars.assetsSymbols, "-"), vars.specificName, vaultInitAddresses);

        vars.vaultManagerTokenId = IVaultManager(IPlatform(vars.platform).vaultManager()).mint(msg.sender, vault);

        IVault(vault).initialize(
            IVault.VaultInitializationData({
                platform: vars.platform,
                strategy: strategy,
                name: vars.name,
                symbol: vars.symbol,
                tokenId: vars.vaultManagerTokenId,
                vaultInitAddresses: vaultInitAddresses,
                vaultInitNums: vaultInitNums
            })
        );

        $.deployedVaults.push(vault);
        $.vaultStatus[vault] = VaultStatusLib.ACTIVE;
        $.isStrategy[strategy] = true;
        $.deploymentKey[vars.deploymentKey] = vault;
        
        FactoryLib.vaultPostDeploy(vars.platform, vault, vaultType, vaultInitAddresses, vaultInitNums);

        emit VaultAndStrategy(
            msg.sender,
            vaultType,
            strategyId,
            vault,
            strategy,
            vars.name,
            vars.symbol,
            vars.assets,
            vars.deploymentKey,
            vars.vaultManagerTokenId
        );
    }

    /// @inheritdoc IFactory
    function upgradeVaultProxy(address vault) external nonReentrant {
        FactoryStorage storage $ = _getStorage();
        if($.vaultStatus[vault] != VaultStatusLib.ACTIVE){
            revert NotActiveVault();
        }
        IVaultProxy proxy = IVaultProxy(vault);
        bytes32 vaultTypeHash = proxy.VAULT_TYPE_HASH();
        address oldImplementation = proxy.implementation();
        VaultConfig memory tempVaultConfig = $.vaultConfig[vaultTypeHash];
        address newImplementation = tempVaultConfig.implementation;
        if(!tempVaultConfig.upgradeAllowed){
            revert UpgradeDenied(vaultTypeHash);
        }
        if(oldImplementation == newImplementation){
            revert AlreadyLastVersion(vaultTypeHash);
        }
        proxy.upgrade();
        emit VaultProxyUpgraded(vault, oldImplementation, newImplementation);
    }

    /// @inheritdoc IFactory
    function upgradeStrategyProxy(address strategyProxy) external nonReentrant {
        FactoryStorage storage $ = _getStorage();
        if(!$.isStrategy[strategyProxy]){
            revert NotStrategy();
        }
        IStrategyProxy proxy = IStrategyProxy(strategyProxy);
        bytes32 idHash = proxy.STRATEGY_IMPLEMENTATION_LOGIC_ID_HASH();
        StrategyLogicConfig storage config = $.strategyLogicConfig[idHash];
        address oldImplementation = proxy.implementation();
        address newImplementation = config.implementation;
        if(!config.upgradeAllowed){
            revert UpgradeDenied(idHash);
        }
        if(oldImplementation == newImplementation){
            revert AlreadyLastVersion(idHash);
        }
        proxy.upgrade();
        emit StrategyProxyUpgraded(strategyProxy, oldImplementation, newImplementation);
    }

    //endregion -- User actions ----

    //region ----- View functions -----

    /// @inheritdoc IFactory
    function vaultTypes() external view returns (
        string[] memory vaultType,
        address[] memory implementation,
        bool[] memory deployAllowed,
        bool[] memory upgradeAllowed,
        uint[] memory buildingPrice,
        bytes32[] memory extra
    ) {
        FactoryStorage storage $ = _getStorage();
        bytes32[] memory hashes = $.vaultTypeHashes.values();
        uint len = hashes.length;
        vaultType = new string[](len);
        implementation = new address[](len);
        deployAllowed = new bool[](len);
        upgradeAllowed = new bool[](len);
        buildingPrice = new uint[](len);
        extra = new bytes32[](len);
        for (uint i; i < len; ++i) {
            VaultConfig memory config = $.vaultConfig[hashes[i]];
            vaultType[i] = config.vaultType;
            implementation[i] = config.implementation;
            deployAllowed[i] = config.deployAllowed;
            upgradeAllowed[i] = config.upgradeAllowed;
            buildingPrice[i] = config.buildingPrice;
            extra[i] = IVault(config.implementation).extra();
        }
    }

    /// @inheritdoc IFactory
    function strategies() external view returns (
        string[] memory id,
        bool[] memory deployAllowed,
        bool[] memory upgradeAllowed,
        bool[] memory farming,
        uint[] memory tokenId,
        string[] memory tokenURI,
        bytes32[] memory extra
    ) {
        FactoryStorage storage $ = _getStorage();
        bytes32[] memory hashes = $.strategyLogicIdHashes.values();
        uint len = hashes.length;
        id = new string[](len);
        deployAllowed = new bool[](len);
        upgradeAllowed = new bool[](len);
        farming = new bool[](len);
        tokenId = new uint[](len);
        tokenURI = new string[](len);
        extra = new bytes32[](len);
        IStrategyLogic strategyLogicNft = IStrategyLogic(IPlatform(platform()).strategyLogic());
        for (uint i; i < len; ++i) {
            StrategyLogicConfig memory config = $.strategyLogicConfig[hashes[i]];
            id[i] = config.id;
            deployAllowed[i] = config.deployAllowed;
            upgradeAllowed[i] = config.upgradeAllowed;
            farming[i] = config.farming;
            tokenId[i] = config.tokenId;
            tokenURI[i] = strategyLogicNft.tokenURI(config.tokenId);
            extra[i] = IStrategy(config.implementation).extra();
        }
    }

    /// @inheritdoc IFactory
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
    ) {
        return FactoryLib.whatToBuild(platform());
    }

    /// @inheritdoc IFactory
    function deployedVaultsLength() external view returns (uint) {
        FactoryStorage storage $ = _getStorage();
        return $.deployedVaults.length;
    }

    /// @inheritdoc IFactory
    function deployedVaults() external view returns (address[] memory) {
        FactoryStorage storage $ = _getStorage();
        return $.deployedVaults;
    }

    /// @inheritdoc IFactory
    function deployedVault(uint id) external view returns (address) {
        FactoryStorage storage $ = _getStorage();
        return $.deployedVaults[id];
    }

    /// @inheritdoc IFactory
    function farmsLength() external view returns (uint) {
        FactoryStorage storage $ = _getStorage();
        return $.farms.length;
    }

    /// @inheritdoc IFactory
    function farms() external view returns (Farm[] memory) {
        FactoryStorage storage $ = _getStorage();
        return $.farms;
    }

    /// @inheritdoc IFactory
    function strategyLogicIdHashes() external view returns (bytes32[] memory) {
        FactoryStorage storage $ = _getStorage();
        return $.strategyLogicIdHashes.values();
    }

    /// @inheritdoc IFactory
    function farm(uint id) external view returns (Farm memory) {
        FactoryStorage storage $ = _getStorage();
        return $.farms[id];
    }

    /// @inheritdoc IFactory
    function getStrategyData(string memory vaultType, address strategyAddress, address bbAsset) public view returns (
        string memory strategyId,
        address[] memory assets,
        string[] memory assetsSymbols,
        string memory specificName,
        string memory vaultSymbol
    ) {
        //slither-disable-next-line unused-return
        return FactoryLib.getStrategyData(vaultType, strategyAddress, bbAsset);
    }

    /// @inheritdoc IFactory
    function getExchangeAssetIndex(address[] memory assets) external view returns (uint) {
        //slither-disable-next-line unused-return
        return FactoryLib.getExchangeAssetIndex(platform(), assets);
    }

    /// @inheritdoc IFactory
    function getDeploymentKey(
        string memory vaultType,
        string memory strategyId,
        address[] memory initVaultAddresses,
        uint[] memory initVaultNums,
        address[] memory initStrategyAddresses,
        uint[] memory initStrategyNums,
        int24[] memory initStrategyTicks
    ) public pure returns (bytes32) {
        //slither-disable-next-line unused-return
        return FactoryLib.getDeploymentKey(
            vaultType,
            strategyId,
            initVaultAddresses,
            initVaultNums,
            initStrategyAddresses,
            initStrategyNums,
            initStrategyTicks,
            [1,0,0,1,0]
        );
    }

    /// @inheritdoc IFactory
    function deploymentKey(bytes32 deploymentKey_) external view returns (address) {
        FactoryStorage storage $ = _getStorage();
        return $.deploymentKey[deploymentKey_];
    }

    /// @inheritdoc IFactory
    function strategyLogicConfig(bytes32 idHash) external view returns (StrategyLogicConfig memory config) {
        FactoryStorage storage $ = _getStorage();
        config = $.strategyLogicConfig[idHash];
    }

    /// @inheritdoc IFactory
    function vaultConfig(bytes32 typeHash) external view returns (
        string memory vaultType,
        address implementation,
        bool deployAllowed,
        bool upgradeAllowed,
        uint buildingPrice
    ) {
        FactoryStorage storage $ = _getStorage();
        VaultConfig memory vaultConfig_ = $.vaultConfig[typeHash];
        (vaultType, implementation, deployAllowed, upgradeAllowed, buildingPrice) = (vaultConfig_.vaultType, vaultConfig_.implementation, vaultConfig_.deployAllowed, vaultConfig_.upgradeAllowed, vaultConfig_.buildingPrice);
    }

    /// @inheritdoc IFactory
    function vaultStatus(address vault) external view returns (uint status) {
        FactoryStorage storage $ = _getStorage();
        status = $.vaultStatus[vault];
    }

    /// @inheritdoc IFactory
    function isStrategy(address address_) external view returns (bool) {
        return _getStorage().isStrategy[address_];
    }

    /// @inheritdoc IFactory
    function vaultsBuiltByPermitTokenId(uint week, uint builderPermitTokenId) external view returns (uint vaultsBuilt) {
        return _getStorage().vaultsBuiltByPermitTokenId[week][builderPermitTokenId];
    }

    //endregion -- View functions -----

    //region ----- Internal logic -----

    function _getStorage() private pure returns (FactoryStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := FACTORY_STORAGE_LOCATION
        }
    }
    
    //endregion -- Internal logic -----

}
