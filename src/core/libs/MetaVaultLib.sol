// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IMetaVault} from "../../interfaces/IMetaVault.sol";
import {IControllable} from "../../interfaces/IControllable.sol";
import {IStabilityVault} from "../../interfaces/IStabilityVault.sol";
import {IVault} from "../../interfaces/IVault.sol";
import {CommonLib} from "../libs/CommonLib.sol";
import {VaultTypeLib} from "../libs/VaultTypeLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPriceReader} from "../../interfaces/IPriceReader.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";

library MetaVaultLib {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint public constant USD_THRESHOLD = 1e13;

    /// @notice Vault can be removed if its TVL is less than this value
    uint public constant USD_THRESHOLD_REMOVE_VAULT = USD_THRESHOLD * 1000; // 1 cent

    //region --------------------------------- Data types
    struct WithdrawUnderlyingLocals {
        uint vaultSharePriceUsd;
        uint totalSupply;
        uint balance;
        uint totalUnderlying;
        uint totalAmounts;
        address[] assets;
        uint[] minAmounts;
        uint[] amountsOut;
    }
    //endregion --------------------------------- Data types

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

    function withdrawUnderlyingEmergency(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        address cVault_,
        address[] memory owners,
        uint[] memory amounts,
        uint[] memory minUnderlyingOut
    ) external returns (uint[] memory amountsOut, uint[] memory recoveryAmountOut, uint[] memory sharesToBurn) {
        //slither-disable-next-line uninitialized-local
        WithdrawUnderlyingLocals memory v;

        address _targetVault = _getTargetVault($, cVault_);

        uint len = owners.length;
        require(len == amounts.length && len == minUnderlyingOut.length, IControllable.IncorrectArrayLength());

        v.totalSupply = _totalSupply($, platform_);

        amountsOut = new uint[](len);
        sharesToBurn = new uint[](len);

        {
            uint _totalShares = $.totalShares;
            for (uint i; i < len; ++i) {
                v.balance = _balanceOf($, owners[i], v.totalSupply);
                if (amounts[i] == 0) {
                    amounts[i] = v.balance;
                } else {
                    require(
                        amounts[i] <= v.balance, IERC20Errors.ERC20InsufficientBalance(owners[i], v.balance, amounts[i])
                    );
                }
                require(amounts[i] != 0, IControllable.IncorrectBalance());
                v.totalAmounts += amounts[i];
                sharesToBurn[i] = _amountToShares(amounts[i], _totalShares, v.totalSupply);
                require(sharesToBurn[i] != 0, IMetaVault.ZeroSharesToBurn(amounts[i]));
            }
            require(v.totalAmounts != 0, IControllable.IncorrectZeroArgument());
        }

        // don't check last block protection here, because it is an emergency withdraw
        // _beforeDepositOrWithdraw($, owner);

        // ensure that the target vault has required amount of meta-vault tokens
        // todo how to check it for all users? require(total <= maxWithdrawUnderlying(cVault_, owner), TooHighAmount());

        (v.vaultSharePriceUsd,) = IStabilityVault(_targetVault).price();

        v.assets = new address[](1);
        v.assets[0] = IVault(cVault_).strategy().underlying();

        v.amountsOut = new uint[](1);
        v.minAmounts = new uint[](1);

        if (_targetVault == cVault_) {
            // withdraw underlying from the target cVault vault
            v.amountsOut = IStabilityVault(_targetVault).withdrawAssets(
                v.assets,
                _getTargetVaultSharesToWithdraw($, platform_, v.totalAmounts, v.vaultSharePriceUsd, true),
                v.minAmounts,
                address(this),
                address(this)
            );
            v.totalUnderlying = v.amountsOut[0];
        } else {
            // withdraw underlying from the child meta-vault
            v.totalUnderlying = IMetaVault(_targetVault).withdrawUnderlying(
                cVault_,
                _getTargetVaultSharesToWithdraw($, platform_, v.totalAmounts, v.vaultSharePriceUsd, true),
                0,
                address(this),
                address(this)
            );
        }

        recoveryAmountOut = new uint[](len);
        for (uint i; i < len; ++i) {
            // burn shares should be called outside
            v.amountsOut[0] = Math.mulDiv(v.totalUnderlying, amounts[i], v.totalAmounts, Math.Rounding.Floor);
            amountsOut[i] = v.amountsOut[0];
            require(
                v.amountsOut[0] >= minUnderlyingOut[i],
                IStabilityVault.ExceedSlippage(v.amountsOut[0], minUnderlyingOut[i])
            );
            IERC20(IVault(cVault_).strategy().underlying()).transfer(owners[i], amountsOut[i]);

            // disable last block protection in the emergency
            // $.lastTransferBlock[owners[i]] = block.number;

            if (!$.lastBlockDefenseWhitelist[msg.sender]) {
                // todo mint receipt/recovery token in amount amount[i] for owners[i]

                // todo emit event with amount of recovery tokens

                emit IStabilityVault.WithdrawAssets(msg.sender, owners[i], v.assets, amounts[i], v.amountsOut);
            } else {
                // the caller is a wrapped/meta-vault
                // it mints its own recovery tokens
            }
        }

        // todo we can have not zero underlying balance in result .. do we need to do anything with it?

        return (amountsOut, recoveryAmountOut, sharesToBurn);
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

    function _withdrawUnderlying(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        address targetVault_,
        address cVault_,
        uint amount,
        uint minUnderlyingOut,
        address receiver,
        address owner,
        bool mintReceiptToken
    ) external returns (uint underlyingOut, uint sharesToBurn) {
        //slither-disable-next-line uninitialized-local
        WithdrawUnderlyingLocals memory v;

        require(amount != 0, IControllable.IncorrectZeroArgument());

        v.totalSupply = _totalSupply($, platform_);
        {
            uint balance = _balanceOf($, owner, v.totalSupply);
            require(amount <= balance, IERC20Errors.ERC20InsufficientBalance(owner, balance, amount));
        }

        sharesToBurn = _amountToShares(amount, $.totalShares, v.totalSupply);
        require(sharesToBurn != 0, IMetaVault.ZeroSharesToBurn(amount));

        // ensure that the target vault has required amount of meta-vault tokens
        {
            uint maxAmount = _maxWithdrawUnderlying($, platform_, cVault_, owner);
            require(amount <= maxAmount, IMetaVault.TooHighAmount(amount, maxAmount));
        }

        (v.vaultSharePriceUsd,) = IStabilityVault(targetVault_).price();

        v.assets = new address[](1);
        v.assets[0] = IVault(cVault_).strategy().underlying();

        v.minAmounts = new uint[](1);
        v.minAmounts[0] = minUnderlyingOut;

        if (targetVault_ == cVault_) {
            // withdraw underlying from the target cVault vault
            v.amountsOut = IStabilityVault(targetVault_).withdrawAssets(
                v.assets,
                _getTargetVaultSharesToWithdraw($, platform_, amount, v.vaultSharePriceUsd, true),
                v.minAmounts,
                receiver,
                address(this)
            );
            underlyingOut = v.amountsOut[0];
        } else {
            // withdraw underlying from the child meta-vault
            underlyingOut = IMetaVault(targetVault_).withdrawUnderlying(
                cVault_,
                _getTargetVaultSharesToWithdraw($, platform_, amount, v.vaultSharePriceUsd, true),
                minUnderlyingOut,
                receiver,
                address(this)
            );
        }

        // burning and updating defense-last-block is implemented outside

        if (mintReceiptToken) {
            // todo mint receipt/recovery token if the cVault is broken one

            // todo emit event
        }

        emit IStabilityVault.WithdrawAssets(msg.sender, owner, v.assets, amount, v.amountsOut);
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

    /// @notice Find meta vault that contains the given {cVault_}
    /// @dev Assume here that there are max 2 meta vaults in the circle: meta vault - meta vault - c-vault
    function _getTargetVault(
        IMetaVault.MetaVaultStorage storage $,
        address cVault_
    ) internal view returns (address targetVault) {
        // check if cVault belongs to the current MetaVault
        address[] memory _vaults = $.vaults;
        for (uint i; i < _vaults.length; ++i) {
            if (_vaults[i] == cVault_) {
                return _vaults[i];
            }
        }

        // check if cVault belongs to one of the sub-meta-vaults
        for (uint i; i < _vaults.length; ++i) {
            address[] memory subVaults = IMetaVault(_vaults[i]).vaults();
            for (uint j; j < subVaults.length; ++j) {
                if (subVaults[j] == cVault_) {
                    return _vaults[i]; // return the parent vault of the sub-vault
                }
            }
        }

        revert IMetaVault.VaultNotFound(cVault_);
    }

    /// @notice Get the target shares to withdraw from the vault for the given {amount}.
    /// @param amount Amount of meta-vault tokens
    /// @param vaultSharePriceUsd Price of the vault shares in USD
    /// @param revertOnLessThanThreshold If true, reverts if the USD amount to withdraw is less than the threshold.
    /// @return targetVaultSharesToWithdraw Amount of shares to withdraw from the vault
    function _getTargetVaultSharesToWithdraw(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        uint amount,
        uint vaultSharePriceUsd,
        bool revertOnLessThanThreshold
    ) internal view returns (uint targetVaultSharesToWithdraw) {
        uint usdToWithdraw = _metaVaultBalanceToUsdAmount($, platform_, amount);
        if (usdToWithdraw > USD_THRESHOLD) {
            return Math.mulDiv(usdToWithdraw, 1e18, vaultSharePriceUsd, Math.Rounding.Floor);
        } else {
            if (revertOnLessThanThreshold) {
                revert IMetaVault.UsdAmountLessThreshold(usdToWithdraw, USD_THRESHOLD);
            }
            return 0;
        }
    }

    function _amountToShares(uint amount, uint totalShares_, uint totalSupply_) internal pure returns (uint) {
        if (totalSupply_ == 0) {
            return 0;
        }
        return Math.mulDiv(amount, totalShares_, totalSupply_, Math.Rounding.Floor);
    }

    function _balanceOf(
        IMetaVault.MetaVaultStorage storage $,
        address account,
        uint totalSupply_
    ) internal view returns (uint) {
        uint _totalShares = $.totalShares;
        if (_totalShares == 0) {
            return 0;
        }
        return Math.mulDiv($.shareBalance[account], totalSupply_, _totalShares, Math.Rounding.Floor);
    }

    function _metaVaultBalanceToUsdAmount(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        uint amount
    ) internal view returns (uint) {
        (uint priceAsset,) = _price($, platform_);
        return Math.mulDiv(amount, priceAsset, 1e18, Math.Rounding.Ceil);
    }

    function _price(
        IMetaVault.MetaVaultStorage storage $,
        address platform_
    ) public view returns (uint price_, bool trusted_) {
        address _pegAsset = $.pegAsset;
        if (_pegAsset == address(0)) {
            return (1e18, true);
        }
        (price_, trusted_) = IPriceReader(IPlatform(platform_).priceReader()).getPrice(_pegAsset);
    }

    function _tvl(
        IMetaVault.MetaVaultStorage storage $,
        address platform_
    ) internal view returns (uint tvl_, bool trusted_) {
        IPriceReader priceReader = IPriceReader(IPlatform(platform_).priceReader());
        bool notSafePrice;

        // get deposited TVL of used vaults
        address[] memory _vaults = $.vaults;
        uint len = _vaults.length;
        for (uint i; i < len; ++i) {
            (uint vaultSharePrice, bool safe) = priceReader.getVaultPrice(_vaults[i]);
            if (!safe) {
                notSafePrice = true;
            }
            uint vaultSharesBalance = IERC20(_vaults[i]).balanceOf(address(this));
            tvl_ += Math.mulDiv(vaultSharePrice, vaultSharesBalance, 1e18, Math.Rounding.Floor);
        }

        // get TVL of assets on contract balance
        address[] memory _assets = $.assets.values();
        len = _assets.length;
        uint[] memory assetsOnBalance = new uint[](len);
        for (uint i; i < len; ++i) {
            assetsOnBalance[i] = IERC20(_assets[i]).balanceOf(address(this));
        }
        (uint assetsTvlUsd,,, bool trustedAssetsPrices) = priceReader.getAssetsPrice(_assets, assetsOnBalance);
        tvl_ += assetsTvlUsd;
        if (!trustedAssetsPrices) {
            notSafePrice = true;
        }

        trusted_ = !notSafePrice;
    }

    function _totalSupply(IMetaVault.MetaVaultStorage storage $, address platform_) internal view returns (uint) {
        // totalSupply is balance of peg asset
        (uint tvlUsd,) = _tvl($, platform_);
        (uint priceAsset,) = _price($, platform_);
        return Math.mulDiv(tvlUsd, 1e18, priceAsset, Math.Rounding.Floor);
    }

    /// @dev Shared implementation for {maxWithdraw} and {maxWithdrawAmountTx}
    /// @param vault Vault to withdraw
    /// @param vaultSharesToWithdraw Amount of shares to withdraw from the {vault}
    /// @return maxAmount Amount of meta-vault tokens to withdraw
    /// @return vaultSharePrice Price of the {vault}
    function _maxAmountToWithdrawFromVaultForShares(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        address vault,
        uint vaultSharesToWithdraw
    ) internal view returns (uint maxAmount, uint vaultSharePrice) {
        (vaultSharePrice,) = IStabilityVault(vault).price();
        uint vaultUsd = Math.mulDiv(vaultSharePrice, vaultSharesToWithdraw, 1e18, Math.Rounding.Floor);
        // Convert USD amount to MetaVault tokens
        maxAmount = _usdAmountToMetaVaultBalance($, platform_, vaultUsd);
    }

    function _usdAmountToMetaVaultBalance(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        uint usdAmount
    ) internal view returns (uint) {
        (uint priceAsset,) = _price($, platform_);
        return Math.mulDiv(usdAmount, 1e18, priceAsset, Math.Rounding.Floor);
    }

    function _maxWithdrawUnderlying(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        address cVault_,
        address account
    ) public view returns (uint amount) {
        uint userBalance = _balanceOf($, account, _totalSupply($, platform_));

        address _targetVault = _getTargetVault($, cVault_);
        if (_targetVault == cVault_) {
            (uint maxMetaVaultTokensToWithdraw,) = _maxAmountToWithdrawFromVaultForShares(
                $, platform_, _targetVault, IStabilityVault(_targetVault).maxWithdraw(address(this), 1)
            );
            return Math.min(userBalance, maxMetaVaultTokensToWithdraw);
        } else {
            (uint maxMetaVaultTokensToWithdraw,) = _maxAmountToWithdrawFromVaultForShares(
                $, platform_, _targetVault, IMetaVault(_targetVault).maxWithdrawUnderlying(cVault_, address(this))
            );

            return Math.min(userBalance, maxMetaVaultTokensToWithdraw);
        }
    }

    //endregion --------------------------------- Internal logic
}
