// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IMetaVault} from "../../interfaces/IMetaVault.sol";
import {IControllable} from "../../interfaces/IControllable.sol";
import {IStabilityVault} from "../../interfaces/IStabilityVault.sol";
import {CommonLib} from "../libs/CommonLib.sol";
import {VaultTypeLib} from "../libs/VaultTypeLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library MetaVaultLib {
    using EnumerableSet for EnumerableSet.AddressSet;

    //region --------------------------------- Restricted actions
    function addVault(
        IMetaVault.MetaVaultStorage storage $,
        address vault,
        uint[] memory newTargetProportions
    ) external {
        // check vault
        uint len = $.vaults.length;
        for (uint i; i < len; ++i) {
            if ($.vaults[i] == vault) {
                revert IMetaVault.IncorrectVault();
            }
        }

        // check proportions
        require(newTargetProportions.length == $.vaults.length + 1, IControllable.IncorrectArrayLength());
        _checkProportions(newTargetProportions);

        address[] memory vaultAssets = IStabilityVault(vault).assets();

        if (_isMultiVault($)) {
            // check asset
            require(vaultAssets.length == 1, IMetaVault.IncorrectVault());
            require(vaultAssets[0] == $.assets.values()[0], IMetaVault.IncorrectVault());
        } else {
            // add assets
            len = vaultAssets.length;
            for (uint i; i < len; ++i) {
                $.assets.add(vaultAssets[i]);
            }
        }

        // add vault
        $.vaults.push(vault);
        $.targetProportions = newTargetProportions;

        emit IMetaVault.AddVault(vault);
        emit IMetaVault.TargetProportions(newTargetProportions);
    }

    function removeVault(IMetaVault.MetaVaultStorage storage $, address vault, uint usdThreshold_) external {
        // ----------------------------- get vault index
        address[] memory _vaults = $.vaults;
        uint vaultIndex = type(uint).max;
        uint len = _vaults.length;
        for (uint i; i < len; ++i) {
            if (_vaults[i] == vault) {
                vaultIndex = i;
                break;
            }
        }

        require(vaultIndex != type(uint).max, IMetaVault.IncorrectVault());

        // ----------------------------- The proportions of the vault should be zero
        uint[] memory _targetProportions = $.targetProportions;
        require(_targetProportions[vaultIndex] == 0, IMetaVault.IncorrectProportions());

        // ----------------------------- Total deposited amount should be less then threshold
        uint vaultUsdValue = _getVaultUsdAmount(vault);
        require(vaultUsdValue < usdThreshold_, IMetaVault.UsdAmountLessThreshold(vaultUsdValue, usdThreshold_));

        // ----------------------------- Remove vault
        if (vaultIndex != len - 1) {
            $.vaults[vaultIndex] = _vaults[len - 1];
            $.targetProportions[vaultIndex] = _targetProportions[len - 1];
        }

        $.vaults.pop();
        $.targetProportions.pop();

        _targetProportions = $.targetProportions;
        _checkProportions(_targetProportions);

        emit IMetaVault.RemoveVault(vault);
        emit IMetaVault.TargetProportions(_targetProportions);
    }
    //endregion --------------------------------- Restricted actions

    //region --------------------------------- View functions
    function currentProportions(IMetaVault.MetaVaultStorage storage $)
        external
        view
        returns (uint[] memory proportions)
    {
        return _currentProportions($);
    }

    function vaultForDeposit(IMetaVault.MetaVaultStorage storage $) external view returns (address target) {
        address[] memory _vaults = $.vaults;
        if ($.totalShares == 0) {
            return _vaults[0];
        }
        uint len = _vaults.length;
        uint[] memory _proportions = _currentProportions($);
        uint[] memory _targetProportions = $.targetProportions;
        uint lowProportionDiff;
        target = _vaults[0];
        for (uint i; i < len; ++i) {
            if (_proportions[i] < _targetProportions[i]) {
                uint diff = _targetProportions[i] - _proportions[i];
                if (diff > lowProportionDiff) {
                    lowProportionDiff = diff;
                    target = _vaults[i];
                }
            }
        }
    }

    function vaultForWithdraw(IMetaVault.MetaVaultStorage storage $) external view returns (address target) {
        address[] memory _vaults = $.vaults;
        if ($.totalShares == 0) {
            return _vaults[0];
        }
        uint len = _vaults.length;
        uint[] memory _proportions = _currentProportions($);
        uint[] memory _targetProportions = $.targetProportions;
        uint highProportionDiff;
        target = _vaults[0];
        for (uint i; i < len; ++i) {
            if (_proportions[i] > _targetProportions[i] && _proportions[i] > 1e16) {
                uint diff = _proportions[i] - _targetProportions[i];
                if (diff > highProportionDiff) {
                    highProportionDiff = diff;
                    target = _vaults[i];
                }
            }
        }
    }
    //endregion --------------------------------- View functions

    //region --------------------------------- Internal logic
    function _currentProportions(IMetaVault.MetaVaultStorage storage $)
        internal
        view
        returns (uint[] memory proportions)
    {
        address[] memory _vaults = $.vaults;
        if ($.totalShares == 0) {
            return $.targetProportions;
        }
        uint len = _vaults.length;
        proportions = new uint[](len);
        uint[] memory vaultUsdValue = new uint[](len);
        uint totalDepositedTvl;
        for (uint i; i < len; ++i) {
            vaultUsdValue[i] = MetaVaultLib._getVaultUsdAmount(_vaults[i]);
            totalDepositedTvl += vaultUsdValue[i];
        }
        for (uint i; i < len; ++i) {
            proportions[i] =
                totalDepositedTvl == 0 ? 0 : Math.mulDiv(vaultUsdValue[i], 1e18, totalDepositedTvl, Math.Rounding.Floor);
        }
    }

    function _getVaultUsdAmount(address vault) internal view returns (uint) {
        (uint vaultTvl,) = IStabilityVault(vault).tvl();
        uint vaultSharesBalance = IERC20(vault).balanceOf(address(this));
        uint vaultTotalSupply = IERC20(vault).totalSupply();
        return
            vaultTotalSupply == 0 ? 0 : Math.mulDiv(vaultSharesBalance, vaultTvl, vaultTotalSupply, Math.Rounding.Floor);
    }

    function _checkProportions(uint[] memory proportions_) internal pure {
        uint len = proportions_.length;
        uint total;
        for (uint i; i < len; ++i) {
            total += proportions_[i];
        }
        require(total == 1e18, IMetaVault.IncorrectProportions());
    }

    function _isMultiVault(IMetaVault.MetaVaultStorage storage $) internal view returns (bool) {
        return CommonLib.eq($._type, VaultTypeLib.MULTIVAULT);
    }
    //endregion --------------------------------- Internal logic
}
