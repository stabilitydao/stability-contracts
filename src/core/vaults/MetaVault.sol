// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Controllable, IControllable} from "../base/Controllable.sol";
import {IMetaVault, IStabilityVault, EnumerableSet} from "../../interfaces/IMetaVault.sol";
import {IPriceReader} from "../../interfaces/IPriceReader.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IHardWorker} from "../../interfaces/IHardWorker.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MetaVaultLib} from "../libs/MetaVaultLib.sol";

/// @title Stability MetaVault implementation
/// @dev Rebase vault that deposit to other vaults
/// Changelog:
///   1.6.0: add vault manager - #408
///   1.5.0: withdrawUnderlying - #360
///   1.4.2: add cachePrices - #348, use USD_THRESHOLD_REMOVE_VAULT in removeVault
///   1.4.1: add LastBlockDefenseDisableMode
///   1.4.0: - add maxDeposit, implement multi-deposit for MultiVault - #330
///          - add whitelist for last-block-defense - #330
///          - add removeVault - #336
///          - add MetaVaultLib to reduce contract size
///   1.3.0: - Add maxWithdraw - #326
///          - MultiVault withdraws from all sub-vaults - #334
///   1.2.3: - fix slippage check in deposit - #303
///          - check provided assets in deposit/withdrawAssets, clear unused approvals - #308
///   1.2.2: USD_THRESHOLD is decreased from to 1e13 to pass Balancer ERC4626 tests
///   1.2.1: use mulDiv - #300
///   1.2.0: add vault to MetaVault; decrease USD_THRESHOLD to 1e14 (0.0001 USDC)
///   1.1.0: IStabilityVault.lastBlockDefenseDisabled()
/// @author Alien Deployer (https://github.com/a17)
/// @author dvpublic (https://github.com/dvpublic)
/// @author Omriss (https://github.com/omriss)
contract MetaVault is Controllable, ReentrancyGuardUpgradeable, IERC20Errors, IMetaVault {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    //region --------------------------------- Constants and transient
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.6.0";

    /// @dev Delay between deposits/transfers and withdrawals
    uint internal constant _TRANSFER_DELAY_BLOCKS = 5;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.MetaVault")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant _METAVAULT_STORAGE_LOCATION =
        0x303154e675d2f93642b6b4ae068c749c9b8a57de9202c6344dbbb24ab936f000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         Transient                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Allow to temporally disable last-block-defence in the current tx
    /// Can be changed by whitelisted strategies only.
    /// Store block number of the transaction that disabled last-block-defense.
    uint internal transient _lastBlockDefenseDisabledTx;
    IMetaVault.LastBlockDefenseDisableMode internal transient _lastBlockDefenseDisabledMode;

    address internal transient _cachedVaultForDeposit;
    address internal transient _cachedVaultForWithdraw;
    //endregion --------------------------------- Constants and transient

    //region --------------------------------- Data types
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct DepositAssetsVars {
        address targetVault;
        uint totalSupplyBefore;
        uint totalSharesBefore;
        uint depositedTvl;
        uint[] amountsConsumed;
    }

    struct DepositToMultiVaultLocals {
        uint targetVaultSharesBefore;
        uint targetVaultPrice;
        uint targetVaultSharesAfter;
        uint[] balanceBefore;
        uint[] amountToDeposit;
        uint[] amounts;
    }
    //endregion --------------------------------- Data types

    //region --------------------------------- Initialization
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
    //endregion --------------------------------- Initialization

    //region --------------------------------- Modifiers
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Marks a function as only callable by the owner.
    modifier onlyAllowedOperator() virtual {
        _requiredAllowedOperator();
        _;
    }

    modifier onlyVaultManager() virtual {
        _requireVaultManager();
        _;
    }
    //endregion --------------------------------- Modifiers

    //region --------------------------------- Restricted action
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMetaVault
    function setTargetProportions(uint[] memory newTargetProportions) external onlyVaultManager {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        require(newTargetProportions.length == $.vaults.length, IControllable.IncorrectArrayLength());
        MetaVaultLib._checkProportions(newTargetProportions);
        $.targetProportions = newTargetProportions;
        emit TargetProportions(newTargetProportions);
    }

    /// @inheritdoc IMetaVault
    function rebalance(
        uint[] memory withdrawShares,
        uint[] memory depositAmountsProportions
    ) external onlyAllowedOperator returns (uint[] memory proportions, int cost) {
        MetaVaultLib._checkProportions(depositAmountsProportions);

        MetaVaultStorage storage $ = _getMetaVaultStorage();
        uint len = $.vaults.length;
        require(
            len == withdrawShares.length && len == depositAmountsProportions.length,
            IControllable.IncorrectArrayLength()
        );

        (uint tvlBefore,) = tvl();

        if (MetaVaultLib.isMultiVault($)) {
            MetaVaultLib.rebalanceMultiVault($, withdrawShares, depositAmountsProportions);
        } else {
            revert NotSupported();
        }

        (uint tvlAfter,) = tvl();
        cost = int(tvlBefore) - int(tvlAfter);
        proportions = currentProportions();
        emit Rebalance(withdrawShares, depositAmountsProportions, cost);
    }

    /// @inheritdoc IMetaVault
    function addVault(address vault, uint[] memory newTargetProportions) external onlyVaultManager {
        MetaVaultLib.addVault(_getMetaVaultStorage(), vault, newTargetProportions);
    }

    /// @inheritdoc IMetaVault
    function removeVault(address vault) external onlyVaultManager {
        MetaVaultLib.removeVault(_getMetaVaultStorage(), vault, MetaVaultLib.USD_THRESHOLD_REMOVE_VAULT);
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

    /// @inheritdoc IMetaVault
    function changeWhitelist(address addr, bool addToWhitelist) external onlyOperator {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        $.lastBlockDefenseWhitelist[addr] = addToWhitelist;

        emit WhitelistChanged(addr, addToWhitelist);
    }

    /// @inheritdoc IMetaVault
    function setLastBlockDefenseDisabledTx(uint disableMode) external {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        require($.lastBlockDefenseWhitelist[msg.sender], NotWhitelisted());

        _lastBlockDefenseDisabledTx =
            disableMode == uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0) ? 0 : block.number;

        _lastBlockDefenseDisabledMode = IMetaVault.LastBlockDefenseDisableMode(disableMode);
    }

    /// @inheritdoc IMetaVault
    function cachePrices(bool clear) external {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        require($.lastBlockDefenseWhitelist[msg.sender], NotWhitelisted());

        MetaVaultLib.cachePrices($, IPriceReader(IPlatform(platform()).priceReader()), clear);
        (_cachedVaultForDeposit, _cachedVaultForWithdraw) =
            clear ? (address(0), address(0)) : MetaVaultLib.vaultForDepositWithdraw($);
    }

    /// @inheritdoc IMetaVault
    function withdrawUnderlyingEmergency(
        address cVault_,
        address[] memory owners,
        uint[] memory amounts,
        uint[] memory minUnderlyingOut,
        bool[] memory pausedRecoveryTokens
    ) external override nonReentrant returns (uint[] memory amountsOut, uint[] memory recoveryAmountOut) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        if (!$.lastBlockDefenseWhitelist[msg.sender]) {
            _requireGovernanceOrMultisig();
        }

        uint[] memory sharesToBurn;
        (amountsOut, recoveryAmountOut, sharesToBurn) = MetaVaultLib.withdrawUnderlyingEmergency(
            $, [platform(), cVault_], owners, amounts, minUnderlyingOut, pausedRecoveryTokens
        );

        uint len = owners.length;
        for (uint i; i < len; ++i) {
            _burn($, owners[i], amounts[i], sharesToBurn[i]);
            // don't update last block protection here, because it is an emergency withdraw
        }

        return (amountsOut, recoveryAmountOut);
    }

    /// @inheritdoc IMetaVault
    function setRecoveryToken(address cVault_, address recoveryToken_) external onlyOperator {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        $.recoveryTokens[cVault_] = recoveryToken_;
    }

    function setVaultManager(address vaultManager_) external onlyGovernanceOrMultisig {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        $.vaultManager = vaultManager_;

        emit SetVaultManager(vaultManager_);
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
        MetaVaultStorage storage $ = _getMetaVaultStorage();

        _beforeDepositOrWithdraw($, receiver);

        //slither-disable-next-line uninitialized-local
        DepositAssetsVars memory v;
        v.targetVault = vaultForDeposit();
        v.totalSupplyBefore = totalSupply();
        v.totalSharesBefore = $.totalShares;

        // ensure that provided assets correspond to the target vault
        // assume that user should call {assetsForDeposit} before calling this function and get correct list of assets
        MetaVaultLib.checkProvidedAssets(assets_, v.targetVault);

        (v.amountsConsumed, v.depositedTvl) = (MetaVaultLib.isMultiVault($))
            ? _depositToMultiVault(v.targetVault, $.vaults, assets_, amountsMax)
            : _depositToTargetVault(v.targetVault, assets_, amountsMax);

        {
            uint balanceOut = _usdAmountToMetaVaultBalance(v.depositedTvl);
            uint sharesToCreate;
            if (v.totalSharesBefore == 0) {
                sharesToCreate = balanceOut;
            } else {
                sharesToCreate = MetaVaultLib.amountToShares(balanceOut, v.totalSharesBefore, v.totalSupplyBefore);
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

    /// @inheritdoc IMetaVault
    function withdrawUnderlying(
        address cVault_,
        uint amount,
        uint minUnderlyingOut,
        address receiver,
        address owner
    ) external override nonReentrant returns (uint underlyingOut) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();

        _beforeDepositOrWithdraw($, owner);

        uint sharesToBurn;
        (underlyingOut, sharesToBurn) =
            MetaVaultLib._withdrawUnderlying($, platform(), cVault_, amount, minUnderlyingOut, receiver, owner);

        _burn($, owner, amount, sharesToBurn);
        $.lastTransferBlock[receiver] = block.number;

        return underlyingOut;
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
        MetaVaultStorage storage $ = _getMetaVaultStorage();

        _checkLastBlockProtection($, from);
        MetaVaultLib.transferFrom($, platform(), from, to, amount);
        _update($, from, to, amount);

        return true;
    }
    //endregion --------------------------------- User actions

    //region --------------------------------- View functions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMetaVault
    function USD_THRESHOLD() external pure override returns (uint) {
        return MetaVaultLib.USD_THRESHOLD;
    }

    /// @inheritdoc IMetaVault
    function currentProportions() public view returns (uint[] memory proportions) {
        return MetaVaultLib.currentProportions(_getMetaVaultStorage());
    }

    /// @inheritdoc IMetaVault
    function targetProportions() public view returns (uint[] memory) {
        return _getMetaVaultStorage().targetProportions;
    }

    /// @inheritdoc IMetaVault
    function vaultForDeposit() public view returns (address target) {
        if (_cachedVaultForDeposit != address(0)) {
            return _cachedVaultForDeposit;
        }
        (target,) = MetaVaultLib.vaultForDepositWithdraw(_getMetaVaultStorage());
    }

    /// @inheritdoc IMetaVault
    function assetsForDeposit() external view returns (address[] memory) {
        return IStabilityVault(vaultForDeposit()).assets();
    }

    /// @inheritdoc IMetaVault
    /// @dev MultiVault supports withdrawing from all sub-vaults. Return the vault from which to start withdrawing.
    function vaultForWithdraw() public view returns (address target) {
        if (_cachedVaultForWithdraw != address(0)) {
            return _cachedVaultForWithdraw;
        }
        (, target) = MetaVaultLib.vaultForDepositWithdraw(_getMetaVaultStorage());
    }

    /// @inheritdoc IMetaVault
    function assetsForWithdraw() external view returns (address[] memory) {
        return IStabilityVault(vaultForWithdraw()).assets();
    }

    /// @inheritdoc IMetaVault
    function maxWithdrawAmountTx() external view returns (uint maxAmount) {
        (maxAmount,) =
            MetaVaultLib._maxAmountToWithdrawFromVault(_getMetaVaultStorage(), platform(), vaultForWithdraw());
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
        return MetaVaultLib.internalSharePrice(_getMetaVaultStorage(), platform());
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
        return MetaVaultLib.previewDepositAssets(
            _getMetaVaultStorage(), platform(), vaultForDeposit(), assets_, amountsMax
        );
    }

    /// @inheritdoc IStabilityVault
    function price() public view returns (uint price_, bool trusted_) {
        return MetaVaultLib.price(_getMetaVaultStorage(), platform());
    }

    /// @inheritdoc IStabilityVault
    function tvl() public view returns (uint tvl_, bool trusted_) {
        return MetaVaultLib.tvl(_getMetaVaultStorage(), platform());
    }

    /// @inheritdoc IStabilityVault
    function lastBlockDefenseDisabled() external view returns (bool) {
        return _getMetaVaultStorage().lastBlockDefenseDisabled;
    }

    /// @inheritdoc IERC20
    function totalSupply() public view returns (uint _tvl) {
        return MetaVaultLib.totalSupply(_getMetaVaultStorage(), platform());
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view returns (uint) {
        return MetaVaultLib.balanceOf(_getMetaVaultStorage(), account, totalSupply());
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

    /// @inheritdoc IMetaVault
    function whitelisted(address addr) external view returns (bool) {
        return _getMetaVaultStorage().lastBlockDefenseWhitelist[addr];
    }

    /// @inheritdoc IStabilityVault
    function maxWithdraw(address account) external view virtual returns (uint amount) {
        return maxWithdraw(account, 0);
    }

    /// @inheritdoc IStabilityVault
    function maxWithdraw(address account, uint mode) public view virtual returns (uint amount) {
        uint userBalance = balanceOf(account);
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        address platform_ = platform();

        return MetaVaultLib.isMultiVault($)
            ? MetaVaultLib.maxWithdrawMultiVault($, platform_, userBalance, mode)
            : MetaVaultLib.maxWithdrawMetaVault($, platform_, userBalance, vaultForWithdraw(), mode);
    }

    /// @inheritdoc IStabilityVault
    function maxDeposit(address account) external view returns (uint[] memory maxAmounts) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        return MetaVaultLib.isMultiVault($)
            ? MetaVaultLib.maxDepositMultiVault($, account)
            : IStabilityVault(vaultForDeposit()).maxDeposit(account);
    }

    /// @inheritdoc IMetaVault
    function maxWithdrawUnderlying(address cVault_, address account) public view override returns (uint amount) {
        return MetaVaultLib.maxWithdrawUnderlying(_getMetaVaultStorage(), platform(), cVault_, account);
    }

    /// @inheritdoc IMetaVault
    function recoveryToken(address cVault_) external view override returns (address) {
        return _getMetaVaultStorage().recoveryTokens[cVault_];
    }

    function vaultManager() external view returns (address) {
        return _getMetaVaultStorage().vaultManager;
    }
    //endregion --------------------------------- View functions

    //region --------------------------------- Internal logic
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _update(MetaVaultStorage storage $, address from, address to, uint amount) internal {
        if (!$.lastBlockDefenseDisabled) {
            if (_lastBlockDefenseDisabledMode != IMetaVault.LastBlockDefenseDisableMode.DISABLE_TX_DONT_UPDATE_MAPS_2) {
                $.lastTransferBlock[to] = block.number;
                $.lastTransferBlock[from] = block.number;
            }
        }
        emit Transfer(from, to, amount);
    }

    function _beforeDepositOrWithdraw(MetaVaultStorage storage $, address owner) internal {
        _checkLastBlockProtection($, owner);
        if (!$.lastBlockDefenseDisabled) {
            if (_lastBlockDefenseDisabledMode != IMetaVault.LastBlockDefenseDisableMode.DISABLE_TX_DONT_UPDATE_MAPS_2) {
                $.lastTransferBlock[owner] = block.number;
            }
        }
    }

    function _checkLastBlockProtection(MetaVaultStorage storage $, address owner) internal view {
        if (
            // defence is not disabled by governance
            // defence is not disabled by whitelisted strategy in the current block
            !$.lastBlockDefenseDisabled && _lastBlockDefenseDisabledTx != block.number
                && $.lastTransferBlock[owner] + _TRANSFER_DELAY_BLOCKS >= block.number
        ) {
            revert WaitAFewBlocks();
        }
    }

    function _depositToTargetVault(
        address targetVault_,
        address[] memory assets_,
        uint[] memory amountsMax
    ) internal returns (uint[] memory amountsConsumed, uint depositedTvl) {
        uint len = assets_.length;
        uint[] memory balanceBefore = new uint[](len);
        amountsConsumed = new uint[](len);

        uint targetVaultSharesBefore = IERC20(targetVault_).balanceOf(address(this));

        for (uint i; i < len; ++i) {
            IERC20(assets_[i]).safeTransferFrom(msg.sender, address(this), amountsMax[i]);
            balanceBefore[i] = IERC20(assets_[i]).balanceOf(address(this));
            IERC20(assets_[i]).forceApprove(targetVault_, amountsMax[i]);
        }

        IStabilityVault(targetVault_).depositAssets(assets_, amountsMax, 0, address(this));

        for (uint i; i < len; ++i) {
            amountsConsumed[i] = balanceBefore[i] - IERC20(assets_[i]).balanceOf(address(this));
            uint refund = amountsMax[i] - amountsConsumed[i];
            if (refund != 0) {
                IERC20(assets_[i]).safeTransfer(msg.sender, refund);
            }
            if (IERC20(assets_[i]).allowance(address(this), targetVault_) != 0) {
                IERC20(assets_[i]).forceApprove(targetVault_, 0);
            }
        }

        // slither-disable-next-line unused-return
        (uint targetVaultPrice,) = IStabilityVault(targetVault_).price();
        uint targetVaultSharesAfter = IERC20(targetVault_).balanceOf(address(this));

        depositedTvl =
            Math.mulDiv(targetVaultSharesAfter - targetVaultSharesBefore, targetVaultPrice, 1e18, Math.Rounding.Floor);
    }

    function _depositToMultiVault(
        address targetVault_,
        address[] memory vaults_,
        address[] memory assets_,
        uint[] memory amountsMax
    ) internal returns (uint[] memory amountsConsumed, uint depositedTvl) {
        // slither-disable-next-line uninitialized-local
        DepositToMultiVaultLocals memory v;

        // find target vault and move it to the first position
        // assume that the order of the other vaults does not matter
        MetaVaultLib.setTargetVaultFirst(targetVault_, vaults_);

        uint len = assets_.length;
        amountsConsumed = new uint[](len);

        // ------------------- receive initial amounts from the user
        v.balanceBefore = new uint[](len);
        v.amountToDeposit = new uint[](len);
        for (uint i; i < len; ++i) {
            IERC20(assets_[i]).safeTransferFrom(msg.sender, address(this), amountsMax[i]);
            v.balanceBefore[i] = IERC20(assets_[i]).balanceOf(address(this));
            v.amountToDeposit[i] = amountsMax[i];
        }

        // ------------------- deposit amounts to sub-vaults
        v.amounts = new uint[](len);
        for (uint n; n < vaults_.length; ++n) {
            v.targetVaultSharesBefore = IERC20(vaults_[n]).balanceOf(address(this));

            uint[] memory _maxDeposit = IStabilityVault(vaults_[n]).maxDeposit(address(this));
            for (uint i; i < len; ++i) {
                v.amounts[i] = Math.min(v.amountToDeposit[i], _maxDeposit[i]);
                IERC20(assets_[i]).forceApprove(vaults_[n], v.amounts[i]);
            }

            IStabilityVault(vaults_[n]).depositAssets(assets_, v.amounts, 0, address(this));

            // slither-disable-next-line uninitialized-state
            bool needToDepositMore;

            for (uint i; i < len; ++i) {
                // maxDeposit should be successfully deposited
                // so, we don't need to clear allowance here
                // we do it safety for edge cases only
                if (IERC20(assets_[i]).allowance(address(this), vaults_[n]) != 0) {
                    IERC20(assets_[i]).forceApprove(vaults_[n], 0);
                }

                amountsConsumed[i] = v.balanceBefore[i] - IERC20(assets_[i]).balanceOf(address(this));
                v.amountToDeposit[i] = amountsMax[i] - amountsConsumed[i];
                needToDepositMore = needToDepositMore || (v.amountToDeposit[i] != 0);
            }

            // slither-disable-next-line unused-return
            (v.targetVaultPrice,) = IStabilityVault(vaults_[n]).price();
            v.targetVaultSharesAfter = IERC20(vaults_[n]).balanceOf(address(this));

            depositedTvl += Math.mulDiv(
                v.targetVaultSharesAfter - v.targetVaultSharesBefore, v.targetVaultPrice, 1e18, Math.Rounding.Floor
            );

            if (!needToDepositMore) break;
        }

        // ------------------- refund remaining amounts
        for (uint i; i < len; ++i) {
            if (v.amountToDeposit[i] != 0) {
                IERC20(assets_[i]).safeTransfer(msg.sender, v.amountToDeposit[i]);
            }
        }

        return (amountsConsumed, depositedTvl);
    }

    function _withdrawAssets(
        address[] memory assets_,
        uint amount,
        uint[] memory minAssetAmountsOut,
        address receiver,
        address owner
    ) internal returns (uint[] memory amountsOut) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();

        _beforeDepositOrWithdraw($, owner);

        address _targetVault = vaultForWithdraw();

        uint sharesToBurn;
        (amountsOut, sharesToBurn) = MetaVaultLib._withdrawAssets(
            $, platform(), _targetVault, assets_, amount, minAssetAmountsOut, receiver, owner
        );

        _burn($, owner, amount, sharesToBurn);
        $.lastTransferBlock[receiver] = block.number;

        return amountsOut;
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

    function _requiredAllowedOperator() internal view {
        address _platform = platform();
        require(
            IPlatform(_platform).isOperator(msg.sender)
                || IHardWorker(IPlatform(_platform).hardWorker()).dedicatedServerMsgSender(msg.sender),
            IControllable.IncorrectMsgSender()
        );
    }

    /// @notice Require that msg.sender is vault manager. If vault manager is not set, require that msg.sender is multisig.
    function _requireVaultManager() internal view {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        address _vaultManager = $.vaultManager;
        if (_vaultManager == address(0)) {
            address _platform = platform();
            _vaultManager = IPlatform(_platform).multisig();
        }
        require(msg.sender == _vaultManager, IControllable.IncorrectMsgSender());
    }

    function _getMetaVaultStorage() internal pure returns (MetaVaultStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _METAVAULT_STORAGE_LOCATION
        }
    }
    //endregion --------------------------------- Internal logic
}
