// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {IFactory} from "../../interfaces/IFactory.sol";
import {IVaultProxy} from "../../interfaces/IVaultProxy.sol";
import {IStrategyProxy} from "../../interfaces/IStrategyProxy.sol";
import {StrategyDeveloperLib} from "../../strategies/libs/StrategyDeveloperLib.sol";
import {IStrategyLogic} from "../../interfaces/IStrategyLogic.sol";
import {IFarmingStrategy} from "../../interfaces/IFarmingStrategy.sol";

library FactoryLib {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    struct GetVaultInitParamsVariantsVars {
        string[] vaultTypes;
        uint total;
        uint totalVaultInitAddresses;
        uint totalVaultInitNums;
        uint len;
    }

    function getExchangeAssetIndex(
        address platform,
        address[] memory assets
    ) external view returns (uint exchangeAssetIndex) {
        address targetExchangeAsset = IPlatform(platform).targetExchangeAsset();
        uint len = assets.length;
        // nosemgrep
        for (uint i; i < len; ++i) {
            if (assets[i] == targetExchangeAsset) {
                return i;
            }
        }

        exchangeAssetIndex = type(uint).max;
        uint minRoutes = type(uint).max;
        ISwapper swapper = ISwapper(IPlatform(platform).swapper());
        // nosemgrep
        for (uint i; i < len; ++i) {
            //slither-disable-next-line unused-return
            (ISwapper.PoolData[] memory route,) = swapper.buildRoute(assets[i], targetExchangeAsset);
            // nosemgrep
            uint routeLength = route.length;
            if (routeLength < minRoutes) {
                minRoutes = routeLength;
                exchangeAssetIndex = i;
            }
        }
        if (exchangeAssetIndex == type(uint).max) {
            revert ISwapper.NoRouteFound();
        }
        if (exchangeAssetIndex > type(uint).max) revert ISwapper.NoRoutesForAssets();
    }

    function getName(
        string memory, /*vaultType*/
        string memory id,
        string memory symbols,
        string memory specificName,
        address[] memory /*vaultInitAddresses*/
    ) public pure returns (string memory name) {
        name = string.concat("Stability ", symbols, " ", id);
        if (keccak256(bytes(specificName)) != keccak256(bytes(""))) {
            name = string.concat(name, " ", specificName);
        }
    }

    function getDeploymentKey(
        string memory vaultType,
        string memory strategyId,
        address[] memory initVaultAddresses,
        uint[] memory initVaultNums,
        address[] memory initStrategyAddresses,
        uint[] memory initStrategyNums,
        int24[] memory initStrategyTicks,
        uint8[5] memory usedValuesForKey
    ) public pure returns (bytes32) {
        uint key = uint(keccak256(abi.encodePacked(vaultType)));
        unchecked {
            key += uint(keccak256(abi.encodePacked(strategyId)));
        }

        uint i;
        uint len;

        // process initVaultAddresses
        len = initVaultAddresses.length;
        if (len > usedValuesForKey[0]) {
            len = usedValuesForKey[0];
        }
        for (; i < len; ++i) {
            unchecked {
                key += uint(uint160(initVaultAddresses[i]));
            }
        }

        // process initVaultNums
        len = initVaultNums.length;
        if (len > usedValuesForKey[1]) {
            len = usedValuesForKey[1];
        }
        for (i = 0; i < len; ++i) {
            unchecked {
                key += initVaultNums[i];
            }
        }

        // process initStrategyAddresses
        len = initStrategyAddresses.length;
        if (len > usedValuesForKey[2]) {
            len = usedValuesForKey[2];
        }
        for (i = 0; i < len; ++i) {
            unchecked {
                key += uint(uint160(initStrategyAddresses[i]));
            }
        }

        // process initStrategyNums
        len = initStrategyNums.length;
        if (len > usedValuesForKey[3]) {
            len = usedValuesForKey[3];
        }
        for (i = 0; i < len; ++i) {
            unchecked {
                key += initStrategyNums[i];
            }
        }

        // process initStrategyTicks
        len = initStrategyTicks.length;
        if (len > usedValuesForKey[4]) {
            len = usedValuesForKey[4];
        }
        for (i = 0; i < len; ++i) {
            unchecked {
                key += initStrategyTicks[i] >= 0 ? uint(int(initStrategyTicks[i])) : uint(-int(initStrategyTicks[i]));
            }
        }

        return bytes32(key);
    }

    function setVaultImplementation(
        IFactory.FactoryStorage storage $,
        string memory vaultType,
        address implementation
    ) external returns (bool needGovOrMultisigAccess) {
        bytes32 typeHash = keccak256(abi.encodePacked(vaultType));
        $.vaultConfig[typeHash] = IFactory.VaultConfig({
            vaultType: vaultType,
            implementation: implementation,
            deployAllowed: true,
            upgradeAllowed: true,
            buildingPrice: 0
        });
        bool newVaultType = $.vaultTypeHashes.add(typeHash);
        if (!newVaultType) {
            needGovOrMultisigAccess = true;
        }
        emit IFactory.VaultConfigChanged(vaultType, implementation, true, true, newVaultType);
    }

    function setStrategyImplementation(
        IFactory.FactoryStorage storage $,
        address platform,
        string memory strategyId,
        address implementation
    ) external returns (bool needGovOrMultisigAccess) {
        bytes32 strategyIdHash = keccak256(bytes(strategyId));
        IFactory.StrategyLogicConfig storage oldConfig = $.strategyLogicConfig[strategyIdHash];
        uint tokenId;
        bool farming;
        if (oldConfig.implementation == address(0)) {
            address developer = StrategyDeveloperLib.getDeveloper(strategyId);
            if (developer == address(0)) {
                developer = IPlatform(platform).multisig();
            }
            tokenId = IStrategyLogic(IPlatform(platform).strategyLogic()).mint(developer, strategyId);
            farming = IERC165(implementation).supportsInterface(type(IFarmingStrategy).interfaceId);
        } else {
            tokenId = oldConfig.tokenId;
            farming = oldConfig.farming;
        }
        $.strategyLogicConfig[strategyIdHash] = IFactory.StrategyLogicConfig({
            id: strategyId,
            tokenId: tokenId,
            implementation: implementation,
            deployAllowed: true,
            upgradeAllowed: true,
            farming: farming
        });
        bool newStrategy = $.strategyLogicIdHashes.add(strategyIdHash);
        needGovOrMultisigAccess = !newStrategy;
        emit IFactory.StrategyLogicConfigChanged(strategyId, implementation, true, true, newStrategy);
    }

    function upgradeVaultProxy(IFactory.FactoryStorage storage $, address vault) external {
        IVaultProxy proxy = IVaultProxy(vault);
        bytes32 vaultTypeHash = proxy.vaultTypeHash();
        address oldImplementation = proxy.implementation();
        IFactory.VaultConfig memory tempVaultConfig = $.vaultConfig[vaultTypeHash];
        address newImplementation = tempVaultConfig.implementation;
        if (oldImplementation == newImplementation) {
            revert IFactory.AlreadyLastVersion(vaultTypeHash);
        }
        proxy.upgrade();
        emit IFactory.VaultProxyUpgraded(vault, oldImplementation, newImplementation);
    }

    function upgradeStrategyProxy(IFactory.FactoryStorage storage $, address strategyProxy) external {
        IStrategyProxy proxy = IStrategyProxy(strategyProxy);
        bytes32 idHash = proxy.strategyImplementationLogicIdHash();
        IFactory.StrategyLogicConfig storage config = $.strategyLogicConfig[idHash];
        address oldImplementation = proxy.implementation();
        address newImplementation = config.implementation;
        if (!config.upgradeAllowed) {
            revert IFactory.UpgradeDenied(idHash);
        }
        if (oldImplementation == newImplementation) {
            revert IFactory.AlreadyLastVersion(idHash);
        }
        proxy.upgrade();
        emit IFactory.StrategyProxyUpgraded(strategyProxy, oldImplementation, newImplementation);
    }
}
