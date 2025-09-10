// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IVaultManager} from "../interfaces/IVaultManager.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {IFrontend} from "../interfaces/IFrontend.sol";

/// @notice Front-end and back-end viewers for platform
/// Changelog:
///   1.1.0: remove RVault and RMVault usage
/// @author Alien Deployer (https://github.com/a17)
contract Frontend is IFrontend {
    string public constant VERSION = "1.1.0";

    error IncorrectParams();

    address public immutable platform;

    struct VaultsVars {
        IPlatform platform;
        IVaultManager vaultManager;
        address[] allVaultAddresses;
        uint len;
        uint k;
    }

    struct WhatToBuildVars {
        bytes32[] strategyIdHashes;
        uint strategyIdHashesLen;
        uint len;
        IPlatform platform;
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

    struct GetVaultInitParamsVariantsVars {
        string[] vaultTypes;
        uint total;
        uint totalVaultInitAddresses;
        uint totalVaultInitNums;
        uint len;
    }

    constructor(address platform_) {
        platform = platform_;
    }

    /// @inheritdoc IFrontend
    function vaults(
        uint start,
        uint pageSize
    )
        external
        view
        returns (
            uint total,
            address[] memory vaultAddress,
            string[] memory name,
            string[] memory symbol,
            string[] memory vaultType,
            uint[] memory sharePrice,
            uint[] memory tvl,
            address[] memory strategy,
            string[] memory strategyId,
            string[] memory strategySpecific
        )
    {
        VaultsVars memory v;
        v.platform = IPlatform(platform);
        v.vaultManager = IVaultManager(v.platform.vaultManager());
        v.allVaultAddresses = v.vaultManager.vaultAddresses();
        total = v.allVaultAddresses.length;

        if (start >= total) {
            revert IncorrectParams();
        }

        v.len = total - start;
        if (v.len > pageSize) {
            v.len = pageSize;
        }

        vaultAddress = new address[](v.len);
        name = new string[](v.len);
        symbol = new string[](v.len);
        vaultType = new string[](v.len);
        tvl = new uint[](v.len);
        sharePrice = new uint[](v.len);
        strategy = new address[](v.len);
        strategyId = new string[](v.len);
        strategySpecific = new string[](v.len);

        for (uint i = start; i < start + v.len; ++i) {
            vaultAddress[v.k] = v.vaultManager.tokenVault(i);
            IVault vault = IVault(vaultAddress[v.k]);
            name[v.k] = IERC20Metadata(vaultAddress[v.k]).name();
            symbol[v.k] = IERC20Metadata(vaultAddress[v.k]).symbol();
            vaultType[v.k] = vault.vaultType();
            strategy[v.k] = address(vault.strategy());
            strategyId[v.k] = IStrategy(strategy[v.k]).strategyLogicId();
            (strategySpecific[v.k],) = IStrategy(strategy[v.k]).getSpecificName();
            (sharePrice[v.k],) = vault.price();
            (tvl[v.k],) = vault.tvl();
            v.k++;
        }
    }

    /// @inheritdoc IFrontend
    function getBalanceAssets(
        address userAccount,
        uint start,
        uint pageSize
    )
        external
        view
        returns (uint total, address[] memory asset, uint[] memory assetPrice, uint[] memory assetUserBalance)
    {
        IPlatform _platform = IPlatform(platform);
        IPriceReader priceReader = IPriceReader(_platform.priceReader());
        address[] memory allAssets = ISwapper(_platform.swapper()).allAssets();

        total = allAssets.length;

        if (start >= total) {
            revert IncorrectParams();
        }

        uint len = total - start;
        if (len > pageSize) {
            len = pageSize;
        }

        asset = new address[](len);
        assetPrice = new uint[](len);
        assetUserBalance = new uint[](len);

        uint k;
        for (uint i = start; i < start + len; ++i) {
            asset[k] = allAssets[i];
            (assetPrice[k],) = priceReader.getPrice(asset[k]);
            assetUserBalance[k] = IERC20(asset[k]).balanceOf(userAccount);
            k++;
        }
    }

    /// @inheritdoc IFrontend
    function getBalanceVaults(
        address userAccount,
        uint start,
        uint pageSize
    )
        external
        view
        returns (uint total, address[] memory vault, uint[] memory vaultSharePrice, uint[] memory vaultUserBalance)
    {
        IPlatform _platform = IPlatform(platform);
        address[] memory allVaultAddresses = IVaultManager(_platform.vaultManager()).vaultAddresses();
        total = allVaultAddresses.length;

        if (start >= total) {
            revert IncorrectParams();
        }

        uint len = total - start;
        if (len > pageSize) {
            len = pageSize;
        }

        vault = new address[](len);
        vaultSharePrice = new uint[](len);
        vaultUserBalance = new uint[](len);
        uint k;
        for (uint i = start; i < start + len; ++i) {
            vault[k] = allVaultAddresses[i];
            (vaultSharePrice[k],) = IVault(vault[k]).price();
            vaultUserBalance[k] = IERC20(vault[k]).balanceOf(userAccount);
            k++;
        }
    }

    /// @inheritdoc IFrontend
    function whatToBuild(
        uint startStrategy,
        uint step
    )
        external
        view
        returns (
            uint totalStrategies,
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

        vars.platform = IPlatform(platform);
        IFactory factory = IFactory(vars.platform.factory());
        vars.strategyIdHashes = factory.strategyLogicIdHashes();
        vars.strategyIdHashesLen = vars.strategyIdHashes.length;
        totalStrategies = vars.strategyIdHashesLen;
        vars.farms = factory.farms();
        vars.farmsLen = vars.farms.length;

        if (startStrategy >= totalStrategies) {
            revert IncorrectParams();
        }

        vars.len = totalStrategies - startStrategy;
        if (vars.len > step) {
            vars.len = step;
        }

        for (vars.i = startStrategy; vars.i < vars.len; ++vars.i) {
            IFactory.StrategyLogicConfig memory strategyConfig;
            //slither-disable-next-line unused-return
            strategyConfig = factory.strategyLogicConfig(vars.strategyIdHashes[vars.i]);

            if (strategyConfig.deployAllowed) {
                (vars.vaultType, vars.usedAddresses, vars.usedNums, vars.allVaultInitAddresses, vars.allVaultInitNums) =
                    _getVaultInitParamsVariants(address(vars.platform), strategyConfig.implementation);
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
                    ) = IStrategy(strategyConfig.implementation).initVariants(address(vars.platform));
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

                        bytes32 _deploymentKey = factory.getDeploymentKey(
                            vars.vaultType[k],
                            strategyConfig.id,
                            vars.vaultInitAddresses,
                            vars.vaultInitNums,
                            vars.strategyInitAddresses,
                            vars.strategyInitNums,
                            vars.strategyInitTicks
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
        for (vars.i = startStrategy; vars.i < vars.len; ++vars.i) {
            IFactory.StrategyLogicConfig memory strategyConfig;
            //slither-disable-next-line unused-return
            strategyConfig = factory.strategyLogicConfig(vars.strategyIdHashes[vars.i]);
            if (strategyConfig.deployAllowed) {
                (vars.vaultType, vars.usedAddresses, vars.usedNums, vars.allVaultInitAddresses, vars.allVaultInitNums) =
                    _getVaultInitParamsVariants(address(vars.platform), strategyConfig.implementation);
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
                    ) = IStrategy(strategyConfig.implementation).initVariants(address(vars.platform));
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

                        bytes32 _deploymentKey = factory.getDeploymentKey(
                            vars.vaultType[k],
                            strategyConfig.id,
                            vars.vaultInitAddresses,
                            vars.vaultInitNums,
                            vars.strategyInitAddresses,
                            vars.strategyInitNums,
                            vars.strategyInitTicks
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
        address/* platform_*/,
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
        for (uint i; i < vars.len; ++i) {
            if (CommonLib.eq(vars.vaultTypes[i], VaultTypeLib.COMPOUNDING)) {
                ++vars.total;
            }
        }
        vaultType = new string[](vars.total);
        usedAddresses = new uint[](vars.total);
        usedNums = new uint[](vars.total);
        allVaultInitAddresses = new address[](vars.totalVaultInitAddresses);
        allVaultInitNums = new uint[](vars.totalVaultInitNums); // now its always 0, but function can be upgraded without changing interface

        // vaultType index, allVaultInitAddresses index, allVaultInitNums index
        uint[3] memory indexes;
        for (uint i; i < vars.len; ++i) {
            if (CommonLib.eq(vars.vaultTypes[i], VaultTypeLib.COMPOUNDING)) {
                vaultType[indexes[0]] = vars.vaultTypes[i];
                ++indexes[0];
            }
        }
    }
}
