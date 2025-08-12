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
import {IMintedERC20} from "../../interfaces/IMintedERC20.sol";

library MetaVaultLib {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Not perform operations with value less than threshold
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
        address recoveryToken;
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

        if (isMultiVault($)) {
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
        require(!isMultiVault($), IMetaVault.IncorrectVault());

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

    /// @notice Withdraw underlying from the vault in emergency mode, don't burn shares
    /// @param platform_ Platform address
    /// @param cVault_ Address of the cVault to withdraw underlying from
    /// @param owners Owners of the shares to withdraw underlying for
    /// @param amounts Amounts of meta-vault tokens to withdraw underlying for each owner
    /// @param minUnderlyingOut Minimal amounts of underlying to receive for each owner
    /// @return amountsOut Amounts of underlying withdrawn for each owner
    /// @return recoveryAmountOut Amounts of recovery tokens minted for each owner
    /// @return sharesToBurn Amounts of shares to burn for each owner
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

        // only broken vaults with not zero recovery token are allowed for emergency withdraw
        v.recoveryToken = $.recoveryTokens[cVault_];
        require(v.recoveryToken != address(0), IMetaVault.RecoveryTokenNotSet(cVault_));

        address _targetVault = _getTargetVault($, cVault_);

        uint len = owners.length;
        require(len == amounts.length && len == minUnderlyingOut.length, IControllable.IncorrectArrayLength());

        v.totalSupply = totalSupply($, platform_);

        amountsOut = new uint[](len);
        sharesToBurn = new uint[](len);

        {
            uint _totalShares = $.totalShares;
            for (uint i; i < len; ++i) {
                v.balance = balanceOf($, owners[i], v.totalSupply);
                if (amounts[i] == 0) {
                    amounts[i] = v.balance;
                } else {
                    require(
                        amounts[i] <= v.balance, IERC20Errors.ERC20InsufficientBalance(owners[i], v.balance, amounts[i])
                    );
                }
                require(amounts[i] != 0, IControllable.IncorrectBalance());
                v.totalAmounts += amounts[i];
                sharesToBurn[i] = amountToShares(amounts[i], _totalShares, v.totalSupply);
                require(sharesToBurn[i] != 0, IMetaVault.ZeroSharesToBurn(amounts[i]));
            }

            // total amount of meta-vault tokens to withdraw underlying for all owners
            require(v.totalAmounts != 0, IControllable.IncorrectZeroArgument());
        }

        // don't check last block protection here, because it is an emergency withdraw
        // _beforeDepositOrWithdraw($, owner);

        // for simplicity we don't check that the target vault has required amount of meta-vault tokens
        // assume that this check will be done in the target vault

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
            // assume that burn shares will be called outside, just report the amount of shares to burn
            v.amountsOut[0] = Math.mulDiv(v.totalUnderlying, amounts[i], v.totalAmounts, Math.Rounding.Floor);
            amountsOut[i] = v.amountsOut[0];
            require(
                v.amountsOut[0] >= minUnderlyingOut[i],
                IStabilityVault.ExceedSlippage(v.amountsOut[0], minUnderlyingOut[i])
            );

            IERC20(IVault(cVault_).strategy().underlying()).transfer(owners[i], amountsOut[i]);
            emit IStabilityVault.WithdrawAssets(msg.sender, owners[i], v.assets, amounts[i], v.amountsOut);

            // disable last block protection in the emergency
            // $.lastTransferBlock[owners[i]] = block.number;

            if (!$.lastBlockDefenseWhitelist[msg.sender]) {
                // 1 meta-vault token => 1 recovery token
                recoveryAmountOut[i] = amounts[i];
                IMintedERC20(v.recoveryToken).mint(owners[i], recoveryAmountOut[i]);
            } else {
                // the caller is a wrapped/meta-vault
                // it mints its own recovery tokens
            }
        }

        // todo we can have not zero (dust) underlying balance in result .. do we need to do anything with it?

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
        address cVault_,
        uint amount,
        uint minUnderlyingOut,
        address receiver,
        address owner
    ) external returns (uint underlyingOut, uint sharesToBurn) {
        //slither-disable-next-line uninitialized-local
        WithdrawUnderlyingLocals memory v;

        if (msg.sender != owner) {
            _spendAllowanceOrBlock($, owner, msg.sender, amount);
        }

        require(amount != 0, IControllable.IncorrectZeroArgument());

        address _targetVault = MetaVaultLib._getTargetVault($, cVault_);

        v.totalSupply = totalSupply($, platform_);
        {
            uint balance = balanceOf($, owner, v.totalSupply);
            require(amount <= balance, IERC20Errors.ERC20InsufficientBalance(owner, balance, amount));
        }

        sharesToBurn = amountToShares(amount, $.totalShares, v.totalSupply);
        require(sharesToBurn != 0, IMetaVault.ZeroSharesToBurn(amount));

        // ensure that the target vault has required amount of meta-vault tokens
        {
            uint maxAmount = maxWithdrawUnderlying($, platform_, cVault_, owner);
            require(amount <= maxAmount, IMetaVault.TooHighAmount(amount, maxAmount));
        }

        (v.vaultSharePriceUsd,) = IStabilityVault(_targetVault).price();

        v.assets = new address[](1);
        v.assets[0] = IVault(cVault_).strategy().underlying();

        v.minAmounts = new uint[](1);
        v.minAmounts[0] = minUnderlyingOut;

        if (_targetVault == cVault_) {
            // withdraw underlying from the target cVault vault
            v.amountsOut = IStabilityVault(_targetVault).withdrawAssets(
                v.assets,
                _getTargetVaultSharesToWithdraw($, platform_, amount, v.vaultSharePriceUsd, true),
                v.minAmounts,
                receiver,
                address(this)
            );
            underlyingOut = v.amountsOut[0];
        } else {
            // withdraw underlying from the child meta-vault
            underlyingOut = IMetaVault(_targetVault).withdrawUnderlying(
                cVault_,
                _getTargetVaultSharesToWithdraw($, platform_, amount, v.vaultSharePriceUsd, true),
                minUnderlyingOut,
                receiver,
                address(this)
            );
        }

        // burning and updating defense-last-block is implemented outside
        if (!$.lastBlockDefenseWhitelist[msg.sender]) {
            // the user is not metavault so recovery tokens should be minted for broken vaults
            address recoveryToken = $.recoveryTokens[cVault_];
            // broken vault has not empty recovery token
            if (recoveryToken != address(0)) {
                IMintedERC20(recoveryToken).mint(receiver, amount);
            }
        }

        emit IStabilityVault.WithdrawAssets(msg.sender, owner, v.assets, amount, v.amountsOut);
    }

    function _withdrawAssets(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        address targetVault_,
        address[] memory assets_,
        uint amount,
        uint[] memory minAssetAmountsOut,
        address receiver,
        address owner
    ) external returns (uint[] memory amountsOut, uint sharesToBurn) {
        // assume that last block defense is already checked in the caller

        if (msg.sender != owner) {
            _spendAllowanceOrBlock($, owner, msg.sender, amount);
        }

        // ensure that provided assets correspond to the target vault
        // assume that user should call {assetsForWithdraw} before calling this function and get correct list of assets
        checkProvidedAssets(assets_, targetVault_);

        require(amount != 0, IControllable.IncorrectZeroArgument());

        uint _totalSupply = totalSupply($, platform_);
        {
            uint balance = balanceOf($, owner, _totalSupply);
            require(amount <= balance, IERC20Errors.ERC20InsufficientBalance(owner, balance, amount));
        }

        require(assets_.length == minAssetAmountsOut.length, IControllable.IncorrectArrayLength());

        sharesToBurn = MetaVaultLib.amountToShares(amount, $.totalShares, _totalSupply);
        require(sharesToBurn != 0, IMetaVault.ZeroSharesToBurn(amount));

        if (MetaVaultLib.isMultiVault($)) {
            // withdraw the amount from all sub-vaults starting from the target vault
            amountsOut = _withdrawFromMultiVault($, platform_, $.vaults, assets_, amount, receiver, targetVault_);

            // check slippage
            for (uint j; j < assets_.length; ++j) {
                require(
                    amountsOut[j] >= minAssetAmountsOut[j],
                    IStabilityVault.ExceedSlippage(amountsOut[j], minAssetAmountsOut[j])
                );
            }
        } else {
            // ensure that the target vault has required amount
            uint vaultSharePriceUsd;
            {
                uint maxAmountToWithdrawFromVault;
                (maxAmountToWithdrawFromVault, vaultSharePriceUsd) =
                    _maxAmountToWithdrawFromVault($, platform_, targetVault_);
                require(
                    amount <= maxAmountToWithdrawFromVault,
                    IMetaVault.MaxAmountForWithdrawPerTxReached(amount, maxAmountToWithdrawFromVault)
                );
            }

            // withdraw the amount from the target vault
            amountsOut = IStabilityVault(targetVault_).withdrawAssets(
                assets_,
                _getTargetVaultSharesToWithdraw($, platform_, amount, vaultSharePriceUsd, true),
                minAssetAmountsOut,
                receiver,
                address(this)
            );
        }

        emit IStabilityVault.WithdrawAssets(msg.sender, owner, assets_, amount, amountsOut);
    }

    function transferFrom(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        address from,
        address to,
        uint amount
    ) external {
        // assume that last block defense is already checked in the caller

        require(to != address(0), IERC20Errors.ERC20InvalidReceiver(to));
        _spendAllowanceOrBlock($, from, msg.sender, amount);

        uint shareTransfer = MetaVaultLib.amountToShares(amount, $.totalShares, totalSupply($, platform_));
        $.shareBalance[from] -= shareTransfer;
        $.shareBalance[to] += shareTransfer;

        // update() should be called in the caller
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

    function isMultiVault(IMetaVault.MetaVaultStorage storage $) internal view returns (bool) {
        return CommonLib.eq($._type, VaultTypeLib.MULTIVAULT);
    }

    function amountToShares(uint amount, uint totalShares_, uint totalSupply_) internal pure returns (uint) {
        return totalSupply_ == 0 ? 0 : Math.mulDiv(amount, totalShares_, totalSupply_, Math.Rounding.Floor);
    }

    function balanceOf(
        IMetaVault.MetaVaultStorage storage $,
        address account,
        uint totalSupply_
    ) internal view returns (uint) {
        uint _totalShares = $.totalShares;
        return _totalShares == 0
            ? 0
            : Math.mulDiv($.shareBalance[account], totalSupply_, _totalShares, Math.Rounding.Floor);
    }

    function price(
        IMetaVault.MetaVaultStorage storage $,
        address platform_
    ) public view returns (uint price_, bool trusted_) {
        address _pegAsset = $.pegAsset;
        return _pegAsset == address(0)
            ? (1e18, true)
            : IPriceReader(IPlatform(platform_).priceReader()).getPrice(_pegAsset);
    }

    function tvl(
        IMetaVault.MetaVaultStorage storage $,
        address platform_
    ) public view returns (uint tvl_, bool trusted_) {
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

    function totalSupply(IMetaVault.MetaVaultStorage storage $, address platform_) public view returns (uint) {
        // totalSupply is balance of peg asset
        (uint tvlUsd,) = tvl($, platform_);
        (uint priceAsset,) = price($, platform_);
        return Math.mulDiv(tvlUsd, 1e18, priceAsset, Math.Rounding.Floor);
    }

    function maxWithdrawUnderlying(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        address cVault_,
        address account
    ) public view returns (uint amount) {
        uint userBalance = balanceOf($, account, totalSupply($, platform_));

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

    function internalSharePrice(
        IMetaVault.MetaVaultStorage storage $,
        address platform_
    ) external view returns (uint sharePrice, int apr, uint storedSharePrice, uint storedTime) {
        uint totalShares = $.totalShares;
        if (totalShares != 0) {
            sharePrice = Math.mulDiv(totalSupply($, platform_), 1e18, totalShares, Math.Rounding.Ceil);
            storedSharePrice = $.storedSharePrice;
            storedTime = $.storedTime;
            if (storedTime != 0) {
                apr = _computeApr(sharePrice, int(sharePrice) - int(storedSharePrice), block.timestamp - storedTime);
            }
        }
        return (sharePrice, apr, storedSharePrice, storedTime);
    }

    function previewDepositAssets(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        address _targetVault,
        address[] memory assets_,
        uint[] memory amountsMax
    ) external view returns (uint[] memory amountsConsumed, uint sharesOut, uint valueOut) {
        uint targetVaultSharesOut;
        uint targetVaultStrategyValueOut;
        (uint targetVaultSharePrice,) = IStabilityVault(_targetVault).price();
        (amountsConsumed, targetVaultSharesOut, targetVaultStrategyValueOut) =
            IStabilityVault(_targetVault).previewDepositAssets(assets_, amountsMax);
        {
            uint usdOut = Math.mulDiv(targetVaultSharePrice, targetVaultSharesOut, 1e18, Math.Rounding.Floor);
            sharesOut = _usdAmountToMetaVaultBalance($, platform_, usdOut);
        }
        uint _totalShares = $.totalShares;
        valueOut = _totalShares == 0
            ? sharesOut
            : MetaVaultLib.amountToShares(sharesOut, $.totalShares, totalSupply($, platform_));
    }

    function maxWithdrawMultiVault(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        uint userBalance,
        uint mode
    ) external view returns (uint amount) {
        for (uint i; i < $.vaults.length; ++i) {
            address _targetVault = $.vaults[i];
            (uint maxMetaVaultTokensToWithdraw,) = MetaVaultLib._maxAmountToWithdrawFromVaultForShares(
                $,
                platform_,
                _targetVault,
                mode == 0
                    ? IStabilityVault(_targetVault).maxWithdraw(address(this))
                    : IStabilityVault(_targetVault).maxWithdraw(address(this), mode)
            );
            amount += maxMetaVaultTokensToWithdraw;
            if (userBalance < amount) return userBalance;
        }

        return amount;
    }

    function maxWithdrawMetaVault(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        uint userBalance,
        address _targetVault,
        uint mode
    ) external view returns (uint amount) {
        // Use reverse logic of withdrawAssets() to calculate max amount of MetaVault balance that can be withdrawn
        // The logic is the same as for {_maxAmountToWithdrawFromVault} but balance is taken for the given account
        (uint maxMetaVaultTokensToWithdraw,) = MetaVaultLib._maxAmountToWithdrawFromVaultForShares(
            $,
            platform_,
            _targetVault,
            mode == 0
                ? IStabilityVault(_targetVault).maxWithdraw(address(this))
                : IStabilityVault(_targetVault).maxWithdraw(address(this), mode)
        );

        return Math.min(userBalance, maxMetaVaultTokensToWithdraw);
    }

    function maxDepositMultiVault(
        IMetaVault.MetaVaultStorage storage $,
        address account
    ) external view returns (uint[] memory maxAmounts) {
        // MultiVault supports depositing to all sub-vaults
        // so we need to calculate summary max deposit amounts for all sub-vaults
        // but result cannot exceed type(uint).max
        for (uint i; i < $.vaults.length; ++i) {
            address _targetVault = $.vaults[i];

            if (i == 0) {
                // lazy initialization of maxAmounts
                maxAmounts = new uint[](IStabilityVault(_targetVault).assets().length);
            }
            uint[] memory _amounts = IStabilityVault(_targetVault).maxDeposit(account);
            for (uint j; j < _amounts.length; ++j) {
                if (maxAmounts[j] != type(uint).max) {
                    maxAmounts[j] = _amounts[j] == type(uint).max ? type(uint).max : maxAmounts[j] + _amounts[j];
                }
            }
        }

        return maxAmounts;
    }

    /// @notice Ensures that the assets array corresponds to the assets of the given vault.
    /// For simplicity we assume that the assets cannot be reordered.
    function checkProvidedAssets(address[] memory assets_, address vault) internal view {
        address[] memory assetsToCheck = IStabilityVault(vault).assets();
        if (assets_.length != assetsToCheck.length) {
            revert IControllable.IncorrectArrayLength();
        }
        for (uint i; i < assets_.length; ++i) {
            if (assets_[i] != assetsToCheck[i]) {
                revert IControllable.IncorrectAssetsList(assets_, assetsToCheck);
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

    function _metaVaultBalanceToUsdAmount(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        uint amount
    ) internal view returns (uint) {
        (uint priceAsset,) = price($, platform_);
        return Math.mulDiv(amount, priceAsset, 1e18, Math.Rounding.Ceil);
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
        (uint priceAsset,) = price($, platform_);
        return Math.mulDiv(usdAmount, 1e18, priceAsset, Math.Rounding.Floor);
    }

    /// @notice Withdraw the {amount} from multiple sub-vaults starting with the {targetVault_}.
    /// @dev Slippage is checked outside this function.
    /// @param amount Amount of meta-vault tokens to withdraw.
    function _withdrawFromMultiVault(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        address[] memory vaults_,
        address[] memory assets_,
        uint amount,
        address receiver,
        address targetVault_
    ) internal returns (uint[] memory amountsOut) {
        uint totalAmount = amount;

        // ------------------- set target vault on the first position in vaults_
        setTargetVaultFirst(targetVault_, vaults_);

        // ------------------- withdraw from vaults until requested amount is withdrawn
        uint len = vaults_.length;
        amountsOut = new uint[](assets_.length);
        for (uint i; i < len; ++i) {
            (uint amountToWithdraw, uint targetVaultSharesToWithdraw) =
                _getAmountToWithdrawFromVault($, platform_, vaults_[i], totalAmount, address(this));
            if (targetVaultSharesToWithdraw != 0) {
                uint[] memory _amountsOut = IStabilityVault(vaults_[i]).withdrawAssets(
                    assets_,
                    targetVaultSharesToWithdraw,
                    new uint[](assets_.length), // minAssetAmountsOut is checked outside
                    receiver,
                    address(this)
                );
                for (uint j; j < assets_.length; ++j) {
                    amountsOut[j] += _amountsOut[j];
                }
                totalAmount -= amountToWithdraw;
                if (totalAmount == 0) break;
            }
        }

        // ------------------- ensure that all requested amount is withdrawn
        require(totalAmount == 0, IMetaVault.MaxAmountForWithdrawPerTxReached(amount, amount - totalAmount));

        return amountsOut;
    }

    /// @notice Get the amount to withdraw from the vault and the target shares to withdraw.
    /// The amount is limited by the max withdraw amount of the vault.
    /// @param amount Amount of meta-vault tokens
    /// @param vault Vault to withdraw from
    /// @param owner Owner of the shares to withdraw
    /// @return amountToWithdraw Amount of meta-vault tokens to withdraw
    /// @return targetVaultSharesToWithdraw Amount of shares to withdraw from the vault
    function _getAmountToWithdrawFromVault(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        address vault,
        uint amount,
        address owner
    ) internal view returns (uint amountToWithdraw, uint targetVaultSharesToWithdraw) {
        (uint maxAmount, uint vaultSharePriceUsd) =
            _maxAmountToWithdrawFromVaultForShares($, platform_, vault, IStabilityVault(vault).maxWithdraw(owner));
        amountToWithdraw = Math.min(amount, maxAmount);
        targetVaultSharesToWithdraw =
            MetaVaultLib._getTargetVaultSharesToWithdraw($, platform_, amountToWithdraw, vaultSharePriceUsd, false);
    }

    /// @notice Get the maximum amount of meta-vault tokens that can be withdrawn from the vault
    /// without taking into account maxWithdraw limit.
    function _maxAmountToWithdrawFromVault(
        IMetaVault.MetaVaultStorage storage $,
        address platform_,
        address vault
    ) internal view returns (uint maxAmount, uint vaultSharePrice) {
        return _maxAmountToWithdrawFromVaultForShares($, platform_, vault, IERC20(vault).balanceOf(address(this)));
    }

    /// @notice Find target vault in {vaults} and move it on the first position.
    function setTargetVaultFirst(
        address targetVault,
        address[] memory vaults_
    ) internal pure returns (address[] memory) {
        uint len = vaults_.length;
        for (uint i; i < len; ++i) {
            if (vaults_[i] == targetVault) {
                // first withdraw should be from the target vault
                // the order of other vaults does not matter because the rebalancer is called often enough
                (vaults_[0], vaults_[i]) = (vaults_[i], vaults_[0]);
                break;
            }
        }
        return vaults_;
    }

    function _computeApr(uint tvl_, int earned, uint duration) internal pure returns (int) {
        return (tvl_ == 0 || duration == 0)
            ? int(0)
            : earned * int(1e18) * 100_000 * int(365) / int(tvl_) / int(duration * 1e18 / 1 days);
    }

    function _spendAllowanceOrBlock(
        IMetaVault.MetaVaultStorage storage $,
        address owner,
        address spender,
        uint amount
    ) internal {
        uint currentAllowance = $.allowance[owner][spender];
        if (owner != msg.sender && currentAllowance != type(uint).max) {
            require(
                currentAllowance >= amount, IERC20Errors.ERC20InsufficientAllowance(spender, currentAllowance, amount)
            );
            $.allowance[owner][spender] = currentAllowance - amount;
        }
    }

    //endregion --------------------------------- Internal logic
}
