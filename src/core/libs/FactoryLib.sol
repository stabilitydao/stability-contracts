// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./CommonLib.sol";
import "./VaultTypeLib.sol";
import "../../interfaces/IPlatform.sol";
import "../../interfaces/IStrategy.sol";
import "../../interfaces/ISwapper.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IPriceReader.sol";
import "../../interfaces/IVault.sol";
import "../../interfaces/IRVault.sol";
import "../../interfaces/IVaultProxy.sol";
import "../../interfaces/IStrategyProxy.sol";

library FactoryLib {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    uint public constant BOOST_REWARD_DURATION = 86400 * 30;

    struct WhatToBuildVars {
        bytes32[] strategyIdHashes;
        uint strategyIdHashesLen;
        IFactory.Farm[] farms;
        uint farmsLen;
        string[] vaultTypes;
        uint vaultTypesLen;
        // getVaultInitParamsVariants returns
        string[] vaultType;
        uint[] usedAddresses;
        uint[] usedNums;
        address[] allVaultInitAddresses;
        uint[] allVaultInitNums;
        uint allVaultInitAddressesIndex;
        uint allVaultInitNumsIndex;
        // strategy initVariants returns
        string[] strategyVariantDesc;
        uint strategyVariantDescLen;
        address[] allStrategyInitAddresses;
        uint[] allStrategyInitNums;
        int24[] allStrategyInitTicks;
        uint allStrategyInitAddressesIndex;
        uint allStrategyInitNumsIndex;
        uint allStrategyInitTicksIndex;
        // target vault init params
        address[] vaultInitAddresses;
        uint[] vaultInitNums;
        // target strategy init params
        address[] strategyInitAddresses;
        uint[] strategyInitNums;
        int24[] strategyInitTicks;
        uint usedStrategyInitAddresses;
        uint usedStrategyInitNums;
        uint usedStrategyInitTicks;
        // total results, used for counters too
        uint total;
        uint totalVaultInitAddresses;
        uint totalVaultInitNums;
        uint totalStrategyInitAddresses;
        uint totalStrategyInitNums;
        uint totalStrategyInitTicks;
        // counters and length
        uint i;
        uint j;
        uint c;
    }

    struct VaultPostDeployVars {
        bool isRewardingVaultType;
        uint minInitialBoostDuration;
        uint minInitialBoostPerDay;
    }

    struct GetVaultInitParamsVariantsVars {
        string[] vaultTypes;
        uint total;
        uint totalVaultInitAddresses;
        uint totalVaultInitNums;
        uint len;
    }

    function whatToBuild(address platform)
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
        )
    {
        WhatToBuildVars memory vars;

        IFactory factory = IFactory(IPlatform(platform).factory());
        vars.strategyIdHashes = factory.strategyLogicIdHashes();
        vars.strategyIdHashesLen = vars.strategyIdHashes.length;
        vars.farms = factory.farms();
        vars.farmsLen = vars.farms.length;

        for (; vars.i < vars.strategyIdHashesLen; ++vars.i) {
            IFactory.StrategyLogicConfig memory strategyConfig;
            //slither-disable-next-line unused-return
            strategyConfig = factory.strategyLogicConfig(vars.strategyIdHashes[vars.i]);

            if (strategyConfig.deployAllowed) {
                (vars.vaultType, vars.usedAddresses, vars.usedNums, vars.allVaultInitAddresses, vars.allVaultInitNums) =
                    _getVaultInitParamsVariants(platform, strategyConfig.implementation);
                // nosemgrep
                vars.vaultTypesLen = vars.vaultType.length;

                vars.allVaultInitAddressesIndex = 0;
                vars.allVaultInitNumsIndex = 0;
                // nosemgrep
                for (uint k; k < vars.vaultTypesLen; ++k) {
                    vars.vaultInitAddresses = new address[](vars.usedAddresses[k]);
                    vars.vaultInitNums = new uint[](vars.usedNums[k]);
                    // nosemgrep
                    for (uint j; j < vars.usedAddresses[k]; ++j) {
                        vars.vaultInitAddresses[j] = vars.allVaultInitAddresses[vars.allVaultInitAddressesIndex];
                        ++vars.allVaultInitAddressesIndex;
                    }
                    // nosemgrep
                    for (uint j; j < vars.usedNums[k]; ++j) {
                        vars.vaultInitNums[j] = vars.allVaultInitNums[vars.allVaultInitNumsIndex];
                        ++vars.allVaultInitNumsIndex;
                    }

                    (
                        vars.strategyVariantDesc,
                        vars.allStrategyInitAddresses,
                        vars.allStrategyInitNums,
                        vars.allStrategyInitTicks
                    ) = IStrategy(strategyConfig.implementation).initVariants(platform);
                    vars.allStrategyInitAddressesIndex = 0;
                    vars.allStrategyInitNumsIndex = 0;
                    vars.allStrategyInitTicksIndex = 0;
                    // nosemgrep
                    uint len = vars.strategyVariantDesc.length;
                    for (vars.j = 0; vars.j < len; ++vars.j) {
                        // nosemgrep
                        uint size = vars.allStrategyInitAddresses.length / len;
                        vars.usedStrategyInitAddresses = 0;
                        vars.usedStrategyInitNums = 0;
                        vars.usedStrategyInitTicks = 0;
                        vars.strategyInitAddresses = new address[](size);
                        // nosemgrep
                        for (uint c; c < size; ++c) {
                            vars.strategyInitAddresses[c] =
                                vars.allStrategyInitAddresses[vars.allStrategyInitAddressesIndex];
                            ++vars.allStrategyInitAddressesIndex;
                            ++vars.usedStrategyInitAddresses;
                        }
                        // nosemgrep
                        size = vars.allStrategyInitNums.length / len;
                        vars.strategyInitNums = new uint[](size);
                        // nosemgrep
                        for (uint c; c < size; ++c) {
                            vars.strategyInitNums[c] = vars.allStrategyInitNums[vars.allStrategyInitNumsIndex];
                            ++vars.allStrategyInitNumsIndex;
                            ++vars.usedStrategyInitNums;
                        }
                        // nosemgrep
                        size = vars.allStrategyInitTicks.length / len;
                        vars.strategyInitTicks = new int24[](size);
                        // nosemgrep
                        for (uint c; c < size; ++c) {
                            vars.strategyInitTicks[c] = vars.allStrategyInitTicks[vars.allStrategyInitTicksIndex];
                            ++vars.allStrategyInitTicksIndex;
                            ++vars.usedStrategyInitTicks;
                        }

                        bytes32 _deploymentKey = getDeploymentKey(
                            vars.vaultType[k],
                            strategyConfig.id,
                            vars.vaultInitAddresses,
                            vars.vaultInitNums,
                            vars.strategyInitAddresses,
                            vars.strategyInitNums,
                            vars.strategyInitTicks,
                            [1, 0, 1, 1, 0]
                        );

                        if (factory.deploymentKey(_deploymentKey) == address(0)) {
                            ++vars.total;
                            vars.totalVaultInitAddresses += vars.usedAddresses[k];
                            vars.totalVaultInitNums += vars.usedNums[k];
                            vars.totalStrategyInitAddresses += vars.usedStrategyInitAddresses;
                            vars.totalStrategyInitNums += vars.usedStrategyInitNums;
                            vars.totalStrategyInitTicks += vars.usedStrategyInitTicks;
                        }
                    }
                }
            }
        }

        desc = new string[](vars.total);
        vaultType = new string[](vars.total);
        strategyId = new string[](vars.total);
        initIndexes = new uint[10][](vars.total);
        vaultInitAddresses = new address[](vars.totalVaultInitAddresses);
        vaultInitNums = new uint[](vars.totalVaultInitNums);
        strategyInitAddresses = new address[](vars.totalStrategyInitAddresses);
        strategyInitNums = new uint[](vars.totalStrategyInitNums);
        strategyInitTicks = new int24[](vars.totalStrategyInitTicks);

        vars.total = 0;
        vars.totalVaultInitAddresses = 0;
        vars.totalVaultInitNums = 0;
        vars.totalStrategyInitAddresses = 0;
        vars.totalStrategyInitNums = 0;
        vars.totalStrategyInitTicks = 0;
        for (vars.i = 0; vars.i < vars.strategyIdHashesLen; ++vars.i) {
            IFactory.StrategyLogicConfig memory strategyConfig;
            //slither-disable-next-line unused-return
            strategyConfig = factory.strategyLogicConfig(vars.strategyIdHashes[vars.i]);
            if (strategyConfig.deployAllowed) {
                (vars.vaultType, vars.usedAddresses, vars.usedNums, vars.allVaultInitAddresses, vars.allVaultInitNums) =
                    _getVaultInitParamsVariants(platform, strategyConfig.implementation);
                // nosemgrep
                vars.vaultTypesLen = vars.vaultType.length;

                vars.allVaultInitAddressesIndex = 0;
                vars.allVaultInitNumsIndex = 0;
                // nosemgrep
                for (uint k; k < vars.vaultTypesLen; ++k) {
                    vars.vaultInitAddresses = new address[](vars.usedAddresses[k]);
                    vars.vaultInitNums = new uint[](vars.usedNums[k]);
                    // nosemgrep
                    for (uint j; j < vars.usedAddresses[k]; ++j) {
                        vars.vaultInitAddresses[j] = vars.allVaultInitAddresses[vars.allVaultInitAddressesIndex];
                        ++vars.allVaultInitAddressesIndex;
                    }
                    // nosemgrep
                    for (uint j; j < vars.usedNums[k]; ++j) {
                        vars.vaultInitNums[j] = vars.allVaultInitNums[vars.allVaultInitNumsIndex];
                        ++vars.allVaultInitNumsIndex;
                    }

                    (
                        vars.strategyVariantDesc,
                        vars.allStrategyInitAddresses,
                        vars.allStrategyInitNums,
                        vars.allStrategyInitTicks
                    ) = IStrategy(strategyConfig.implementation).initVariants(platform);
                    vars.allStrategyInitAddressesIndex = 0;
                    vars.allStrategyInitNumsIndex = 0;
                    vars.allStrategyInitTicksIndex = 0;
                    // nosemgrep
                    vars.strategyVariantDescLen = vars.strategyVariantDesc.length;
                    for (vars.j = 0; vars.j < vars.strategyVariantDescLen; ++vars.j) {
                        // nosemgrep
                        uint size = vars.allStrategyInitAddresses.length / vars.strategyVariantDescLen;
                        vars.usedStrategyInitAddresses = 0;
                        vars.usedStrategyInitNums = 0;
                        vars.usedStrategyInitTicks = 0;
                        vars.strategyInitAddresses = new address[](size);
                        // nosemgrep
                        for (uint c; c < size; ++c) {
                            vars.strategyInitAddresses[c] =
                                vars.allStrategyInitAddresses[vars.allStrategyInitAddressesIndex];
                            ++vars.allStrategyInitAddressesIndex;
                            ++vars.usedStrategyInitAddresses;
                        }
                        // nosemgrep
                        size = vars.allStrategyInitNums.length / vars.strategyVariantDescLen;
                        vars.strategyInitNums = new uint[](size);
                        // nosemgrep
                        for (uint c; c < size; ++c) {
                            vars.strategyInitNums[c] = vars.allStrategyInitNums[vars.allStrategyInitNumsIndex];
                            ++vars.allStrategyInitNumsIndex;
                            ++vars.usedStrategyInitNums;
                        }
                        // nosemgrep
                        size = vars.allStrategyInitTicks.length / vars.strategyVariantDescLen;
                        vars.strategyInitTicks = new int24[](size);
                        // nosemgrep
                        for (uint c; c < size; ++c) {
                            vars.strategyInitTicks[c] = vars.allStrategyInitTicks[vars.allStrategyInitTicksIndex];
                            ++vars.allStrategyInitTicksIndex;
                            ++vars.usedStrategyInitTicks;
                        }

                        bytes32 _deploymentKey = getDeploymentKey(
                            vars.vaultType[k],
                            strategyConfig.id,
                            vars.vaultInitAddresses,
                            vars.vaultInitNums,
                            vars.strategyInitAddresses,
                            vars.strategyInitNums,
                            vars.strategyInitTicks,
                            [1, 0, 1, 1, 0]
                        );

                        if (factory.deploymentKey(_deploymentKey) == address(0)) {
                            desc[vars.total] = vars.strategyVariantDesc[vars.j];
                            vaultType[vars.total] = vars.vaultType[k];
                            strategyId[vars.total] = strategyConfig.id;

                            initIndexes[vars.total][0] = vars.totalVaultInitAddresses;
                            initIndexes[vars.total][1] = vars.totalVaultInitAddresses + vars.usedAddresses[k];
                            initIndexes[vars.total][2] = vars.totalVaultInitNums;
                            initIndexes[vars.total][3] = vars.totalVaultInitNums + vars.usedNums[k];
                            initIndexes[vars.total][4] = vars.totalStrategyInitAddresses;
                            initIndexes[vars.total][5] =
                                vars.totalStrategyInitAddresses + vars.usedStrategyInitAddresses;
                            initIndexes[vars.total][6] = vars.totalStrategyInitNums;
                            initIndexes[vars.total][7] = vars.totalStrategyInitNums + vars.usedStrategyInitNums;
                            initIndexes[vars.total][8] = vars.totalStrategyInitTicks;
                            initIndexes[vars.total][9] = vars.totalStrategyInitTicks + vars.usedStrategyInitTicks;
                            // nosemgrep
                            for (uint c; c < vars.usedAddresses[k]; ++c) {
                                vaultInitAddresses[vars.totalVaultInitAddresses + c] = vars.vaultInitAddresses[c];
                            }
                            // nosemgrep
                            for (uint c; c < vars.usedNums[k]; ++c) {
                                vaultInitNums[vars.totalVaultInitNums + c] = vars.vaultInitNums[c];
                            }
                            // nosemgrep
                            for (uint c; c < vars.usedStrategyInitAddresses; ++c) {
                                strategyInitAddresses[vars.totalStrategyInitAddresses + c] =
                                    vars.strategyInitAddresses[c];
                            }
                            // nosemgrep
                            for (uint c; c < vars.usedStrategyInitNums; ++c) {
                                strategyInitNums[vars.totalStrategyInitNums + c] = vars.strategyInitNums[c];
                            }
                            // nosemgrep
                            for (uint c; c < vars.usedStrategyInitTicks; ++c) {
                                strategyInitTicks[vars.totalStrategyInitTicks + c] = vars.strategyInitTicks[c];
                            }

                            ++vars.total;
                            vars.totalVaultInitAddresses += vars.usedAddresses[k];
                            vars.totalVaultInitNums += vars.usedNums[k];
                            vars.totalStrategyInitAddresses += vars.usedStrategyInitAddresses;
                            vars.totalStrategyInitNums += vars.usedStrategyInitNums;
                            vars.totalStrategyInitTicks += vars.usedStrategyInitTicks;
                        }
                    }
                }
            }
        }
    }

    function _getVaultInitParamsVariants(
        address platform,
        address strategyImplementation
    )
        internal
        view
        returns (
            string[] memory vaultType,
            uint[] memory usedAddresses,
            uint[] memory usedNums,
            address[] memory allVaultInitAddresses,
            uint[] memory allVaultInitNums
        )
    {
        GetVaultInitParamsVariantsVars memory vars;
        vars.vaultTypes = IStrategy(strategyImplementation).supportedVaultTypes();
        vars.len = vars.vaultTypes.length;
        //slither-disable-next-line unused-return
        (address[] memory allowedBBTokens,) = IPlatform(platform).allowedBBTokenVaultsFiltered();
        uint allowedBBTokensLen = allowedBBTokens.length;
        // nosemgrep
        for (uint i; i < vars.len; ++i) {
            if (CommonLib.eq(vars.vaultTypes[i], VaultTypeLib.COMPOUNDING)) {
                ++vars.total;
            } else if (
                CommonLib.eq(vars.vaultTypes[i], VaultTypeLib.REWARDING)
                    || CommonLib.eq(vars.vaultTypes[i], VaultTypeLib.REWARDING_MANAGED)
            ) {
                vars.total += allowedBBTokensLen;
                vars.totalVaultInitAddresses += allowedBBTokensLen;
            }
        }
        vaultType = new string[](vars.total);
        usedAddresses = new uint[](vars.total);
        usedNums = new uint[](vars.total);
        allVaultInitAddresses = new address[](vars.totalVaultInitAddresses);
        allVaultInitNums = new uint[](vars.totalVaultInitNums); // now its always 0, but function can be upgraded without changing interface

        // vaultType index, allVaultInitAddresses index, allVaultInitNums index
        uint[3] memory indexes;
        // nosemgrep
        for (uint i; i < vars.len; ++i) {
            if (CommonLib.eq(vars.vaultTypes[i], VaultTypeLib.COMPOUNDING)) {
                vaultType[indexes[0]] = vars.vaultTypes[i];
                ++indexes[0];
            } else if (
                CommonLib.eq(vars.vaultTypes[i], VaultTypeLib.REWARDING)
                    || CommonLib.eq(vars.vaultTypes[i], VaultTypeLib.REWARDING_MANAGED)
            ) {
                // nosemgrep
                for (uint k; k < allowedBBTokensLen; ++k) {
                    vaultType[indexes[0]] = vars.vaultTypes[i];
                    allVaultInitAddresses[indexes[1]] = allowedBBTokens[k];
                    usedAddresses[indexes[0]] = 1;
                    ++indexes[0];
                    ++indexes[1];
                }
            }
        }
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
        string memory vaultType,
        string memory id,
        string memory symbols,
        string memory specificName,
        address[] memory vaultInitAddresses
    ) public view returns (string memory name) {
        name = string.concat("Stability ", symbols, " ", id);
        if (keccak256(bytes(specificName)) != keccak256(bytes(""))) {
            name = string.concat(name, " ", specificName);
        }
        if (keccak256(bytes(vaultType)) == keccak256(bytes(VaultTypeLib.REWARDING))) {
            name = string.concat(name, " ", IERC20Metadata(vaultInitAddresses[0]).symbol(), " reward");
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

    function vaultPostDeploy(
        address platform,
        address vault,
        string memory vaultType,
        address[] memory vaultInitAddresses,
        uint[] memory vaultInitNums
    ) external {
        VaultPostDeployVars memory vars;
        vars.isRewardingVaultType = CommonLib.eq(vaultType, VaultTypeLib.REWARDING);
        if (vars.isRewardingVaultType || CommonLib.eq(vaultType, VaultTypeLib.REWARDING_MANAGED)) {
            IPlatform(platform).useAllowedBBTokenVault(vaultInitAddresses[0]);
            IPriceReader priceReader = IPriceReader(IPlatform(platform).priceReader());
            vars.minInitialBoostDuration = IPlatform(platform).minInitialBoostDuration();
            vars.minInitialBoostPerDay = IPlatform(platform).minInitialBoostPerDay();
            vaultInitAddresses = IRVault(vault).rewardTokens();
            uint boostTokensLen = vaultInitAddresses.length - 1;
            uint totalInitialBoostUsdPerDay;
            // nosemgrep
            for (uint i; i < boostTokensLen; ++i) {
                address token = vaultInitAddresses[1 + i];
                uint durationSeconds = vars.isRewardingVaultType ? BOOST_REWARD_DURATION : vaultInitNums[1 + i];
                if (durationSeconds < vars.minInitialBoostDuration) {
                    revert IFactory.BoostDurationTooLow();
                }
                uint initialNotifyAmount =
                    vars.isRewardingVaultType ? vaultInitNums[i] : vaultInitNums[1 + boostTokensLen + i];
                //slither-disable-next-line unused-return
                (uint price,) = priceReader.getPrice(token);
                totalInitialBoostUsdPerDay += (
                    ((((initialNotifyAmount * 1e18) / 10 ** IERC20Metadata(token).decimals()) * price) / 1e18) * 86400
                ) / durationSeconds;
                if (initialNotifyAmount > 0) {
                    IERC20(token).safeTransferFrom(msg.sender, address(this), initialNotifyAmount);
                    IERC20(token).forceApprove(vault, initialNotifyAmount);
                    IRVault(vault).notifyTargetRewardAmount(1 + i, initialNotifyAmount);
                }
            }
            if (totalInitialBoostUsdPerDay == 0) {
                revert IFactory.BoostAmountIsZero();
            }
            if (totalInitialBoostUsdPerDay < vars.minInitialBoostPerDay) {
                revert IFactory.BoostAmountTooLow();
            }
        }
    }

    function setVaultConfig(
        IFactory.FactoryStorage storage $,
        IFactory.VaultConfig memory vaultConfig_
    ) external returns (bool needGovOrMultisigAccess) {
        string memory type_ = vaultConfig_.vaultType;
        bytes32 typeHash = keccak256(abi.encodePacked(type_));
        $.vaultConfig[typeHash] = vaultConfig_;
        bool newVaultType = $.vaultTypeHashes.add(typeHash);
        if (!newVaultType) {
            needGovOrMultisigAccess = true;
        }
        emit IFactory.VaultConfigChanged(
            type_, vaultConfig_.implementation, vaultConfig_.deployAllowed, vaultConfig_.upgradeAllowed, newVaultType
        );
    }

    function upgradeVaultProxy(IFactory.FactoryStorage storage $, address vault) external {
        IVaultProxy proxy = IVaultProxy(vault);
        bytes32 vaultTypeHash = proxy.vaultTypeHash();
        address oldImplementation = proxy.implementation();
        IFactory.VaultConfig memory tempVaultConfig = $.vaultConfig[vaultTypeHash];
        address newImplementation = tempVaultConfig.implementation;
        if (!tempVaultConfig.upgradeAllowed) {
            revert IFactory.UpgradeDenied(vaultTypeHash);
        }
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
