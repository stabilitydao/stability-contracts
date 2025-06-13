// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Controllable, IControllable} from "../base/Controllable.sol";
import {CommonLib} from "../libs/CommonLib.sol";
import {VaultTypeLib} from "../libs/VaultTypeLib.sol";
import {IMetaVault, IStabilityVault, EnumerableSet} from "../../interfaces/IMetaVault.sol";
import {IPriceReader} from "../../interfaces/IPriceReader.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IHardWorker} from "../../interfaces/IHardWorker.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title Stability MetaVault implementation
/// @dev Rebase vault that deposit to other vaults
/// Changelog:
///   1.2.3: - fix slippage check in deposit - #303
///          - check provided assets in deposit/withdrawAssets, clear unused approvals - #308
///   1.2.2: USD_THRESHOLD is decreased from to 1e13 to pass Balancer ERC4626 tests
///   1.2.1: use mulDiv - #300
///   1.2.0: add vault to MetaVault; decrease USD_THRESHOLD to 1e14 (0.0001 USDC)
///   1.1.0: IStabilityVault.lastBlockDefenseDisabled()
/// @author Alien Deployer (https://github.com/a17)
/// @author dvpublic (https://github.com/dvpublic)
contract MetaVault is Controllable, ReentrancyGuardUpgradeable, IERC20Errors, IMetaVault {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.2.3";

    /// @inheritdoc IMetaVault
    uint public constant USD_THRESHOLD = 1; // todo 1e13;

    /// @dev Delay between deposits/transfers and withdrawals
    uint internal constant _TRANSFER_DELAY_BLOCKS = 5;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.MetaVault")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant _METAVAULT_STORAGE_LOCATION =
        0x303154e675d2f93642b6b4ae068c749c9b8a57de9202c6344dbbb24ab936f000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct DepositAssetsVars {
        address targetVault;
        uint totalSupplyBefore;
        uint totalSharesBefore;
        uint len;
        uint[] balanceBefore;
        uint[] amountsConsumed;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMetaVault
    function initialize(
        address platform_,
        string memory type_,
        address pegAsset_,
        string memory name_,
        string memory symbol_,
        address[] memory vaults_,
        uint[] memory proportions_
    ) public initializer {
        __Controllable_init(platform_);
        __ReentrancyGuard_init();
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        $._type = type_;
        $.vaults = vaults_;
        uint len = vaults_.length;
        EnumerableSet.AddressSet storage _assets = $.assets;
        for (uint i; i < len; ++i) {
            address[] memory __assets = IStabilityVault(vaults_[i]).assets();
            uint assetsLength = __assets.length;
            for (uint k; k < assetsLength; ++k) {
                _assets.add(__assets[k]);
            }
            emit AddVault(vaults_[i]);
        }
        $.targetProportions = proportions_;
        $.pegAsset = pegAsset_;
        $.name = name_;
        $.symbol = symbol_;
        emit TargetProportions(proportions_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Marks a function as only callable by the owner.
    modifier onlyAllowedOperator() virtual {
        _requiredAllowedOperator();
        _;
    }

    //region --------------------------------- Restricted action
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMetaVault
    function setTargetProportions(uint[] memory newTargetProportions) external onlyAllowedOperator {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        require(newTargetProportions.length == $.vaults.length, IControllable.IncorrectArrayLength());
        _checkProportions(newTargetProportions);
        $.targetProportions = newTargetProportions;
        emit TargetProportions(newTargetProportions);
    }

    /// @inheritdoc IMetaVault
    function rebalance(
        uint[] memory withdrawShares,
        uint[] memory depositAmountsProportions
    ) external onlyAllowedOperator returns (uint[] memory proportions, int cost) {
        _checkProportions(depositAmountsProportions);

        MetaVaultStorage storage $ = _getMetaVaultStorage();
        uint len = $.vaults.length;
        require(
            len == withdrawShares.length && len == depositAmountsProportions.length,
            IControllable.IncorrectArrayLength()
        );

        (uint tvlBefore,) = tvl();

        if (CommonLib.eq($._type, VaultTypeLib.MULTIVAULT)) {
            address[] memory _assets = $.assets.values();
            for (uint i; i < len; ++i) {
                if (withdrawShares[i] != 0) {
                    IStabilityVault($.vaults[i]).withdrawAssets(_assets, withdrawShares[i], new uint[](1));
                    require(depositAmountsProportions[i] == 0, IncorrectRebalanceArgs());
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
                    require(withdrawShares[i] == 0, IncorrectRebalanceArgs());
                }
            }
        } else {
            revert NotSupported();
        }

        (uint tvlAfter,) = tvl();
        cost = int(tvlBefore) - int(tvlAfter);
        proportions = currentProportions();
        emit Rebalance(withdrawShares, depositAmountsProportions, cost);
    }

    /// @inheritdoc IMetaVault
    function addVault(address vault, uint[] memory newTargetProportions) external onlyGovernanceOrMultisig {
        MetaVaultStorage storage $ = _getMetaVaultStorage();

        // check vault
        uint len = $.vaults.length;
        for (uint i; i < len; ++i) {
            if ($.vaults[i] == vault) {
                revert IMetaVault.IncorrectVault();
            }
        }

        // check proportions
        require(newTargetProportions.length == $.vaults.length + 1, IncorrectArrayLength());
        _checkProportions(newTargetProportions);

        address[] memory vaultAssets = IStabilityVault(vault).assets();

        if (CommonLib.eq($._type, VaultTypeLib.MULTIVAULT)) {
            // check asset
            require(vaultAssets.length == 1, IncorrectVault());
            require(vaultAssets[0] == $.assets.values()[0], IncorrectVault());
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

        emit AddVault(vault);
        emit TargetProportions(newTargetProportions);
    }

    /// @inheritdoc IMetaVault
    function emitAPR()
        external
        onlyAllowedOperator
        returns (uint sharePrice, int apr, uint lastStoredSharePrice, uint duration)
    {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        uint storedTime;
        (sharePrice, apr, lastStoredSharePrice, storedTime) = internalSharePrice();
        duration = block.timestamp - storedTime;
        $.storedSharePrice = sharePrice;
        $.storedTime = block.timestamp;
        (uint _tvl,) = tvl();
        emit APR(sharePrice, apr, lastStoredSharePrice, duration, _tvl);
    }

    /// @inheritdoc IStabilityVault
    function setName(string calldata newName) external onlyOperator {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        $.name = newName;
        emit VaultName(newName);
    }

    /// @inheritdoc IStabilityVault
    function setSymbol(string calldata newSymbol) external onlyOperator {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        $.symbol = newSymbol;
        emit VaultSymbol(newSymbol);
    }

    /// @inheritdoc IStabilityVault
    function setLastBlockDefenseDisabled(bool isDisabled) external onlyGovernanceOrMultisig {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        $.lastBlockDefenseDisabled = isDisabled;
        emit LastBlockDefenseDisabled(isDisabled);
    }

    //endregion --------------------------------- Restricted action

    //region --------------------------------- User actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStabilityVault
    function depositAssets(
        address[] memory assets_,
        uint[] memory amountsMax,
        uint minSharesOut,
        address receiver
    ) external nonReentrant {
        console.log("MetaVault.depositAssets", amountsMax[0]);
        MetaVaultStorage storage $ = _getMetaVaultStorage();

        _beforeDepositOrWithdraw($, receiver);

        DepositAssetsVars memory v;
        v.targetVault = vaultForDeposit();
        v.totalSupplyBefore = totalSupply();
        v.totalSharesBefore = $.totalShares;
        v.len = assets_.length;
        v.balanceBefore = new uint[](v.len);
        v.amountsConsumed = new uint[](v.len);

        // ensure that provided assets correspond to the target vault
        // assume that user should call {assetsForDeposit} before calling this function and get correct list of assets
        _checkProvidedAssets(assets_, v.targetVault);

        for (uint i; i < v.len; ++i) {
            IERC20(assets_[i]).safeTransferFrom(msg.sender, address(this), amountsMax[i]);
            v.balanceBefore[i] = IERC20(assets_[i]).balanceOf(address(this));
            IERC20(assets_[i]).forceApprove(v.targetVault, amountsMax[i]);
        }

        uint targetVaultSharesBefore = IERC20(v.targetVault).balanceOf(address(this));
        IStabilityVault(v.targetVault).depositAssets(assets_, amountsMax, 0, address(this));
        for (uint i; i < v.len; ++i) {
            v.amountsConsumed[i] = v.balanceBefore[i] - IERC20(assets_[i]).balanceOf(address(this));
            uint refund = amountsMax[i] - v.amountsConsumed[i];
            if (refund != 0) {
                IERC20(assets_[i]).safeTransfer(msg.sender, refund);
            }
            if (IERC20(assets_[i]).allowance(address(this), v.targetVault) != 0) {
                IERC20(assets_[i]).forceApprove(v.targetVault, 0);
            }
        }

        {
            (uint targetVaultPrice,) = IStabilityVault(v.targetVault).price();
            uint targetVaultSharesAfter = IERC20(v.targetVault).balanceOf(address(this));
            uint depositedTvl = Math.mulDiv(
                targetVaultSharesAfter - targetVaultSharesBefore, targetVaultPrice, 1e18, Math.Rounding.Floor
            );
            uint balanceOut = _usdAmountToMetaVaultBalance(depositedTvl);
            uint sharesToCreate;
            if (v.totalSharesBefore == 0) {
                sharesToCreate = balanceOut;
            } else {
                sharesToCreate = _amountToShares(balanceOut, v.totalSharesBefore, v.totalSupplyBefore);
            }

            _mint($, receiver, sharesToCreate, balanceOut);

            if (sharesToCreate < minSharesOut) {
                revert ExceedSlippage(sharesToCreate, minSharesOut);
            }
            // todo dead shares

            emit DepositAssets(receiver, assets_, v.amountsConsumed, balanceOut);
        }

        if ($.storedTime == 0) {
            $.storedTime = block.timestamp;
            ($.storedSharePrice,,,) = internalSharePrice();
        }
    }

    /// @inheritdoc IStabilityVault
    function withdrawAssets(
        address[] memory assets_,
        uint amount,
        uint[] memory minAssetAmountsOut
    ) external nonReentrant returns (uint[] memory) {
        console.log("MetaVault.withdrawAssets", amount);
        return _withdrawAssets(assets_, amount, minAssetAmountsOut, msg.sender, msg.sender);
    }

    /// @inheritdoc IStabilityVault
    function withdrawAssets(
        address[] memory assets_,
        uint amount,
        uint[] memory minAssetAmountsOut,
        address receiver,
        address owner
    ) external nonReentrant returns (uint[] memory amountsOut) {
        return _withdrawAssets(assets_, amount, minAssetAmountsOut, receiver, owner);
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint amount) external returns (bool) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        $.allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @inheritdoc IERC20
    function transfer(address to, uint amount) external returns (bool) {
        transferFrom(msg.sender, to, amount);
        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint amount) public returns (bool) {
        require(to != address(0), ERC20InvalidReceiver(to));
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        _spendAllowanceOrBlock(from, msg.sender, amount);
        _checkLastBlockProtection($, from);
        uint shareTransfer = _amountToShares(amount, $.totalShares, totalSupply());
        $.shareBalance[from] -= shareTransfer;
        $.shareBalance[to] += shareTransfer;
        _update($, from, to, amount);
        return true;
    }
    //endregion --------------------------------- User actions

    //region --------------------------------- View functions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMetaVault
    function currentProportions() public view returns (uint[] memory proportions) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        address[] memory _vaults = $.vaults;
        if ($.totalShares == 0) {
            return targetProportions();
        }
        uint len = _vaults.length;
        proportions = new uint[](len);
        uint[] memory vaultUsdValue = new uint[](len);
        uint totalDepositedTvl;
        for (uint i; i < len; ++i) {
            (uint vaultTvl,) = IStabilityVault(_vaults[i]).tvl();
            uint vaultSharesBalance = IERC20(_vaults[i]).balanceOf(address(this));
            uint vaultTotalSupply = IERC20(_vaults[i]).totalSupply();
            vaultUsdValue[i] = Math.mulDiv(vaultSharesBalance, vaultTvl, vaultTotalSupply, Math.Rounding.Floor);
            totalDepositedTvl += vaultUsdValue[i];
        }
        for (uint i; i < len; ++i) {
            proportions[i] = Math.mulDiv(vaultUsdValue[i], 1e18, totalDepositedTvl, Math.Rounding.Floor);
        }
    }

    /// @inheritdoc IMetaVault
    function targetProportions() public view returns (uint[] memory) {
        return _getMetaVaultStorage().targetProportions;
    }

    /// @inheritdoc IMetaVault
    function vaultForDeposit() public view returns (address target) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        address[] memory _vaults = $.vaults;
        if ($.totalShares == 0) {
            return _vaults[0];
        }
        uint len = _vaults.length;
        uint[] memory _proportions = currentProportions();
        uint[] memory _targetProportions = targetProportions();
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

    /// @inheritdoc IMetaVault
    function assetsForDeposit() external view returns (address[] memory) {
        return IStabilityVault(vaultForDeposit()).assets();
    }

    /// @inheritdoc IMetaVault
    function vaultForWithdraw() public view returns (address target) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        address[] memory _vaults = $.vaults;
        if ($.totalShares == 0) {
            return _vaults[0];
        }
        uint len = _vaults.length;
        uint[] memory _proportions = currentProportions();
        uint[] memory _targetProportions = targetProportions();
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

    /// @inheritdoc IMetaVault
    function assetsForWithdraw() external view returns (address[] memory) {
        return IStabilityVault(vaultForWithdraw()).assets();
    }

    /// @inheritdoc IMetaVault
    function maxWithdrawAmountTx() external view returns (uint maxAmount) {
        (maxAmount,) = _maxAmountToWithdrawFromVault(vaultForWithdraw());
    }

    /// @inheritdoc IMetaVault
    function pegAsset() external view returns (address) {
        return _getMetaVaultStorage().pegAsset;
    }

    /// @inheritdoc IMetaVault
    function vaults() external view returns (address[] memory) {
        return _getMetaVaultStorage().vaults;
    }

    /// @inheritdoc IMetaVault
    function internalSharePrice()
        public
        view
        returns (uint sharePrice, int apr, uint storedSharePrice, uint storedTime)
    {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        uint _totalSupply = totalSupply();
        uint totalShares = $.totalShares;
        if (totalShares == 0) {
            return (0, 0, 0, 0);
        }
        sharePrice = Math.mulDiv(_totalSupply, 1e18, totalShares, Math.Rounding.Ceil);
        storedSharePrice = $.storedSharePrice;
        storedTime = $.storedTime;
        if (storedTime != 0) {
            apr = _computeApr(sharePrice, int(sharePrice) - int(storedSharePrice), block.timestamp - storedTime);
        }
    }

    /// @inheritdoc IStabilityVault
    function assets() external view returns (address[] memory) {
        return _getMetaVaultStorage().assets.values();
    }

    /// @inheritdoc IStabilityVault
    function vaultType() external view returns (string memory) {
        return _getMetaVaultStorage()._type;
    }

    /// @inheritdoc IStabilityVault
    function previewDepositAssets(
        address[] memory assets_,
        uint[] memory amountsMax
    ) external view returns (uint[] memory amountsConsumed, uint sharesOut, uint valueOut) {
        address _targetVault = vaultForDeposit();
        uint targetVaultSharesOut;
        uint targetVaultStrategyValueOut;
        (uint targetVaultSharePrice,) = IStabilityVault(_targetVault).price();
        (amountsConsumed, targetVaultSharesOut, targetVaultStrategyValueOut) =
            IStabilityVault(_targetVault).previewDepositAssets(assets_, amountsMax);
        uint usdOut = Math.mulDiv(targetVaultSharePrice, targetVaultSharesOut, 1e18, Math.Rounding.Floor);
        sharesOut = _usdAmountToMetaVaultBalance(usdOut);
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        uint _totalShares = $.totalShares;
        if (_totalShares == 0) {
            valueOut = sharesOut;
        } else {
            valueOut = _amountToShares(sharesOut, $.totalShares, totalSupply());
        }
    }

    /// @inheritdoc IStabilityVault
    function price() public view returns (uint price_, bool trusted_) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        address _pegAsset = $.pegAsset;
        if (_pegAsset == address(0)) {
            return (1e18, true);
        }
        return IPriceReader(IPlatform(platform()).priceReader()).getPrice(_pegAsset);
    }

    /// @inheritdoc IStabilityVault
    function tvl() public view returns (uint tvl_, bool trusted_) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());
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

    /// @inheritdoc IStabilityVault
    function lastBlockDefenseDisabled() external view returns (bool) {
        return _getMetaVaultStorage().lastBlockDefenseDisabled;
    }

    /// @inheritdoc IERC20
    function totalSupply() public view returns (uint _tvl) {
        // totalSupply is balance of peg asset
        (uint tvlUsd,) = tvl();
        (uint priceAsset,) = price();
        return Math.mulDiv(tvlUsd, 1e18, priceAsset, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view returns (uint) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        uint _totalShares = $.totalShares;
        if (_totalShares == 0) {
            return 0;
        }
        return Math.mulDiv($.shareBalance[account], totalSupply(), _totalShares, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) external view returns (uint) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        return $.allowance[owner][spender];
    }

    /// @inheritdoc IERC20Metadata
    function name() external view returns (string memory) {
        return _getMetaVaultStorage().name;
    }

    /// @inheritdoc IERC20Metadata
    function symbol() external view returns (string memory) {
        return _getMetaVaultStorage().symbol;
    }

    /// @inheritdoc IERC20Metadata
    function decimals() external pure returns (uint8) {
        return 18;
    }
    //endregion --------------------------------- View functions

    //region --------------------------------- Internal logic
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _checkProportions(uint[] memory proportions_) internal pure {
        uint len = proportions_.length;
        uint total;
        for (uint i; i < len; ++i) {
            total += proportions_[i];
        }
        require(total == 1e18, IncorrectProportions());
    }

    function _update(MetaVaultStorage storage $, address from, address to, uint amount) internal {
        if (!$.lastBlockDefenseDisabled) {
            $.lastTransferBlock[from] = block.number;
            $.lastTransferBlock[to] = block.number;
        }
        emit Transfer(from, to, amount);
    }

    function _beforeDepositOrWithdraw(MetaVaultStorage storage $, address owner) internal {
        _checkLastBlockProtection($, owner);
        if (!$.lastBlockDefenseDisabled) {
            $.lastTransferBlock[owner] = block.number;
        }
    }

    function _checkLastBlockProtection(MetaVaultStorage storage $, address owner) internal view {
        if (!$.lastBlockDefenseDisabled && $.lastTransferBlock[owner] + _TRANSFER_DELAY_BLOCKS >= block.number) {
            revert WaitAFewBlocks();
        }
    }

    function _withdrawAssets(
        address[] memory assets_,
        uint amount,
        uint[] memory minAssetAmountsOut,
        address receiver,
        address owner
    ) internal returns (uint[] memory amountsOut) {
        console.log("amount", amount);
        if (msg.sender != owner) {
            _spendAllowanceOrBlock(owner, msg.sender, amount);
        }
        if (amount == 0) {
            revert IControllable.IncorrectZeroArgument();
        }
        if (amount > balanceOf(owner)) {
            revert ERC20InsufficientBalance(owner, balanceOf(owner), amount);
        }
        if (assets_.length != minAssetAmountsOut.length) {
            revert IControllable.IncorrectArrayLength();
        }

        MetaVaultStorage storage $ = _getMetaVaultStorage();

        _beforeDepositOrWithdraw($, owner);

        uint sharesToBurn = _amountToShares(amount, $.totalShares, totalSupply());
        require(sharesToBurn != 0, ZeroSharesToBurn(amount));

        address _targetVault = vaultForWithdraw();

        // ensure that provided assets correspond to the target vault
        // assume that user should call {assetsForWithdraw} before calling this function and get correct list of assets
        _checkProvidedAssets(assets_, _targetVault);

        (uint maxAmountToWithdrawFromVault, uint vaultSharePriceUsd) = _maxAmountToWithdrawFromVault(_targetVault);
        require(
            amount <= maxAmountToWithdrawFromVault,
            MaxAmountForWithdrawPerTxReached(amount, maxAmountToWithdrawFromVault)
        );

        uint usdToWithdraw = _metaVaultBalanceToUsdAmount(amount);

        console.log("usdToWithdraw", usdToWithdraw, USD_THRESHOLD);
        require(usdToWithdraw > USD_THRESHOLD, UsdAmountLessThreshold(usdToWithdraw, USD_THRESHOLD));

        uint targetVaultSharesToWithdraw = Math.mulDiv(usdToWithdraw, 1e18, vaultSharePriceUsd, Math.Rounding.Floor);

        amountsOut = IStabilityVault(_targetVault).withdrawAssets(
            assets_, targetVaultSharesToWithdraw, minAssetAmountsOut, receiver, address(this)
        );

        _burn($, owner, amount, sharesToBurn);

        $.lastTransferBlock[receiver] = block.number;

        emit WithdrawAssets(msg.sender, owner, assets_, amount, amountsOut);
    }

    function _maxAmountToWithdrawFromVault(address vault)
        internal
        view
        returns (uint maxAmount, uint vaultSharePrice)
    {
        (vaultSharePrice,) = IStabilityVault(vault).price();
        uint vaultUsd = Math.mulDiv(vaultSharePrice, IERC20(vault).balanceOf(address(this)), 1e18, Math.Rounding.Floor);
        maxAmount = _usdAmountToMetaVaultBalance(vaultUsd);
    }

    function _burn(MetaVaultStorage storage $, address account, uint amountToBurn, uint sharesToBurn) internal {
        $.totalShares -= sharesToBurn;
        $.shareBalance[account] -= sharesToBurn;
        _update($, account, address(0), amountToBurn);
    }

    function _mint(MetaVaultStorage storage $, address account, uint mintShares, uint mintBalance) internal {
        require(account != address(0), ERC20InvalidReceiver(account));
        $.totalShares += mintShares;
        $.shareBalance[account] += mintShares;
        _update($, address(0), account, mintBalance);
    }

    function _usdAmountToMetaVaultBalance(uint usdAmount) internal view returns (uint) {
        (uint priceAsset,) = price();
        return Math.mulDiv(usdAmount, 1e18, priceAsset, Math.Rounding.Floor);
    }

    function _metaVaultBalanceToUsdAmount(uint amount) internal view returns (uint) {
        (uint priceAsset,) = price();
        console.log("priceAsset", priceAsset);
        return Math.mulDiv(amount, priceAsset, 1e18, Math.Rounding.Ceil);
    }

    function _amountToShares(uint amount, uint totalShares_, uint totalSupply_) internal pure returns (uint) {
        if (totalSupply_ == 0) {
            return 0;
        }
        return Math.mulDiv(amount, totalShares_, totalSupply_, Math.Rounding.Floor);
    }

    function _spendAllowanceOrBlock(address owner, address spender, uint amount) internal {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        uint currentAllowance = $.allowance[owner][spender];
        if (owner != msg.sender && currentAllowance != type(uint).max) {
            require(currentAllowance >= amount, ERC20InsufficientAllowance(spender, currentAllowance, amount));
            $.allowance[owner][spender] = currentAllowance - amount;
        }
    }

    function _computeApr(uint tvl_, int earned, uint duration) internal pure returns (int) {
        if (tvl_ == 0 || duration == 0) {
            return 0;
        }
        return earned * int(1e18) * 100_000 * int(365) / int(tvl_) / int(duration * 1e18 / 1 days);
    }

    function _requiredAllowedOperator() internal view {
        address _platform = platform();
        require(
            IPlatform(_platform).isOperator(msg.sender)
                || IHardWorker(IPlatform(_platform).hardWorker()).dedicatedServerMsgSender(msg.sender),
            IControllable.IncorrectMsgSender()
        );
    }

    function _getMetaVaultStorage() internal pure returns (MetaVaultStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _METAVAULT_STORAGE_LOCATION
        }
    }

    /// @notice Ensures that the assets array corresponds to the assets of the given vault.
    /// For simplicity we assume that the assets cannot be reordered.
    function _checkProvidedAssets(address[] memory assets_, address vault) internal view {
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

    //endregion --------------------------------- Internal logic
}
