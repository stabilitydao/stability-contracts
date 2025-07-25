// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IMetaVault} from "../../interfaces/IMetaVault.sol";
import {IControllable} from "../../interfaces/IControllable.sol";
import {IStabilityVault} from "../../interfaces/IStabilityVault.sol";
import {CommonLib} from "../libs/CommonLib.sol";
import {VaultTypeLib} from "../libs/VaultTypeLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPriceReader} from "../../interfaces/IPriceReader.sol";

library MetaVaultLib {
    using SafeERC20 for IERC20;
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

    function cachePrices(IMetaVault.MetaVaultStorage storage $, IPriceReader priceReader_, bool clear) external {
        require(!_isMultiVault($), IMetaVault.IncorrectVault());

        if (clear) {
            // clear exist cache
            priceReader_.preCalculateVaultPriceTx(address(0));
        } else {
            address[] memory _vaults = $.vaults;
            for (uint i; i < _vaults.length; ++i) {
                address[] memory _subVaults = IMetaVault(_vaults[i]).vaults();
                for (uint j; j < _subVaults.length; ++j) {
                    priceReader_.preCalculateVaultPriceTx(_subVaults[j]);
                }
                priceReader_.preCalculateVaultPriceTx(_subVaults[i]);
            }
        }
    }
    //endregion --------------------------------- Restricted actions

    //region --------------------------------- Actions
    function rebalanceMultiVault(
        IMetaVault.MetaVaultStorage storage $,
        uint[] memory withdrawShares,
        uint[] memory depositAmountsProportions
    ) external {
        uint len = $.vaults.length;
        address[] memory _assets = $.assets.values();
        for (uint i; i < len; ++i) {
            if (withdrawShares[i] != 0) {
                IStabilityVault($.vaults[i]).withdrawAssets(_assets, withdrawShares[i], new uint[](1));
                require(depositAmountsProportions[i] == 0, IMetaVault.IncorrectRebalanceArgs());
            }
        }
        uint totalToDeposit = IERC20(_assets[0]).balanceOf(address(this));
        for (uint i; i < len; ++i) {
            address vault = $.vaults[i];
            uint[] memory amountsMax = new uint[](1);
            amountsMax[0] = depositAmountsProportions[i] * totalToDeposit / 1e18;
            if (amountsMax[0] != 0) {
                IERC20(_assets[0]).forceApprove(vault, amountsMax[0]);
                IStabilityVault(vault).depositAssets(_assets, amountsMax, 0, address(this));
                require(withdrawShares[i] == 0, IMetaVault.IncorrectRebalanceArgs());
            }
        }
    }
    //endregion --------------------------------- Actions

    //region --------------------------------- View functions
    function currentProportions(IMetaVault.MetaVaultStorage storage $)
        external
        view
        returns (uint[] memory proportions)
    {
        return _currentProportions($);
    }

    function vaultForDepositWithdraw(IMetaVault.MetaVaultStorage storage $)
        external
        view
        returns (address targetForDeposit, address targetForWithdraw)
    {
        address[] memory _vaults = $.vaults;
        if ($.totalShares == 0) {
            return (_vaults[0], _vaults[0]);
        }
        uint len = _vaults.length;
        uint[] memory _proportions = _currentProportions($);
        uint[] memory _targetProportions = $.targetProportions;
        uint lowProportionDiff;
        uint highProportionDiff;
        targetForDeposit = _vaults[0];
        targetForWithdraw = _vaults[0];
        for (uint i; i < len; ++i) {
            if (_proportions[i] < _targetProportions[i]) {
                uint diff = _targetProportions[i] - _proportions[i];
                if (diff > lowProportionDiff) {
                    lowProportionDiff = diff;
                    targetForDeposit = _vaults[i];
                }
            } else if (_proportions[i] > _targetProportions[i] && _proportions[i] > 1e16) {
                uint diff = _proportions[i] - _targetProportions[i];
                if (diff > highProportionDiff) {
                    highProportionDiff = diff;
                    targetForWithdraw = _vaults[i];
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
