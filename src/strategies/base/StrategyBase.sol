// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../core/base/Controllable.sol";
import "../../core/libs/VaultTypeLib.sol";
import "../libs/StrategyLib.sol";
import "../../interfaces/IStrategy.sol";
import "../../interfaces/IVault.sol";

/// @dev Base universal strategy
/// Changelog:
///   2.0.0: previewDepositAssetsWrite; use platform.getCustomVaultFee
///   1.1.0: autoCompoundingByUnderlyingProtocol(), virtual total()
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
abstract contract StrategyBase is Controllable, IStrategy {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of StrategyBase implementation
    string public constant VERSION_STRATEGY_BASE = "2.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.StrategyBase")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant STRATEGYBASE_STORAGE_LOCATION =
        0xb14b643f49bed6a2c6693bbd50f68dc950245db265c66acadbfa51ccc8c3ba00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    //slither-disable-next-line naming-convention
    function __StrategyBase_init(
        address platform_,
        string memory id_,
        address vault_,
        address[] memory assets_,
        address underlying_,
        uint exchangeAssetIndex_
    ) internal onlyInitializing {
        __Controllable_init(platform_);
        StrategyBaseStorage storage $ = _getStrategyBaseStorage();
        ($._id, $.vault, $._assets, $._underlying, $._exchangeAssetIndex) =
            (id_, vault_, assets_, underlying_, exchangeAssetIndex_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyVault() {
        _requireVault();
        _;
    }

    /// @inheritdoc IStrategy
    function depositAssets(uint[] memory amounts) external override onlyVault returns (uint value) {
        StrategyBaseStorage storage $ = _getStrategyBaseStorage();
        if ($.lastHardWork == 0) {
            $.lastHardWork = block.timestamp;
        }
        _beforeDeposit();
        return _depositAssets(amounts, true);
    }

    /// @inheritdoc IStrategy
    function withdrawAssets(
        address[] memory assets_,
        uint value,
        address receiver
    ) external virtual onlyVault returns (uint[] memory amountsOut) {
        _beforeWithdraw();
        return _withdrawAssets(assets_, value, receiver);
    }

    function depositUnderlying(uint amount)
        external
        virtual
        override
        onlyVault
        returns (uint[] memory amountsConsumed)
    {
        _beforeDeposit();
        return _depositUnderlying(amount);
    }

    function withdrawUnderlying(uint amount, address receiver) external virtual override onlyVault {
        _beforeWithdraw();
        _withdrawUnderlying(amount, receiver);
    }

    /// @inheritdoc IStrategy
    function transferAssets(
        uint amount,
        uint total_,
        address receiver
    ) external onlyVault returns (uint[] memory amountsOut) {
        _beforeTransferAssets();
        //slither-disable-next-line unused-return
        return StrategyLib.transferAssets(_getStrategyBaseStorage(), amount, total_, receiver);
    }

    /// @inheritdoc IStrategy
    function doHardWork() external onlyVault {
        _beforeDoHardWork();
        StrategyBaseStorage storage $ = _getStrategyBaseStorage();
        address _vault = $.vault;
        //slither-disable-next-line unused-return
        (uint tvl,) = IVault(_vault).tvl();
        if (tvl > 0) {
            address _platform = platform();
            uint exchangeAssetIndex = $._exchangeAssetIndex;

            (
                address[] memory __assets,
                uint[] memory __amounts,
                address[] memory __rewardAssets,
                uint[] memory __rewardAmounts
            ) = _claimRevenue();

            //slither-disable-next-line uninitialized-local
            uint totalBefore;
            if (!autoCompoundingByUnderlyingProtocol()) {
                __amounts[exchangeAssetIndex] +=
                    _liquidateRewards(__assets[exchangeAssetIndex], __rewardAssets, __rewardAmounts);

                uint[] memory amountsRemaining = StrategyLib.extractFees(_platform, _vault, $._id, __assets, __amounts);

                bool needCompound = _processRevenue(__assets, amountsRemaining);

                totalBefore = $.total;

                if (needCompound) {
                    _compound();
                }
            } else {
                // maybe this is not final logic
                // vault shares as fees can be used not only for autoCompoundingByUnderlyingProtocol strategies,
                // but for many strategies linked to CVault if this feature will be implemented
                IVault(_vault).hardWorkMintFeeCallback(__assets, __amounts);
                // call empty method only for coverage or them can be overriden
                _liquidateRewards(__assets[0], __rewardAssets, __rewardAmounts);
                _processRevenue(__assets, __amounts);
                _compound();
            }

            StrategyLib.emitApr($, _platform, __assets, __amounts, tvl, totalBefore);
        }
    }

    /// @inheritdoc IStrategy
    function emergencyStopInvesting() external onlyGovernanceOrMultisig {
        // slither-disable-next-line unused-return
        _withdrawAssets(total(), address(this));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(Controllable, IERC165) returns (bool) {
        return interfaceId == type(IStrategy).interfaceId || super.supportsInterface(interfaceId);
    }

    function strategyLogicId() public view virtual returns (string memory);

    /// @inheritdoc IStrategy
    function assets() public view virtual returns (address[] memory) {
        return _getStrategyBaseStorage()._assets;
    }

    /// @inheritdoc IStrategy
    function underlying() public view override returns (address) {
        return _getStrategyBaseStorage()._underlying;
    }

    /// @inheritdoc IStrategy
    function vault() public view override returns (address) {
        return _getStrategyBaseStorage().vault;
    }

    /// @inheritdoc IStrategy
    function total() public view virtual override returns (uint) {
        return _getStrategyBaseStorage().total;
    }

    /// @inheritdoc IStrategy
    function lastHardWork() public view override returns (uint) {
        return _getStrategyBaseStorage().lastHardWork;
    }

    /// @inheritdoc IStrategy
    function lastApr() public view override returns (uint) {
        return _getStrategyBaseStorage().lastApr;
    }

    /// @inheritdoc IStrategy
    function lastAprCompound() public view override returns (uint) {
        return _getStrategyBaseStorage().lastAprCompound;
    }

    /// @inheritdoc IStrategy
    function assetsAmounts() public view virtual returns (address[] memory assets_, uint[] memory amounts_) {
        (assets_, amounts_) = _assetsAmounts();
        //slither-disable-next-line unused-return
        return StrategyLib.assetsAmountsWithBalances(assets_, amounts_);
    }

    /// @inheritdoc IStrategy
    function previewDepositAssets(
        address[] memory assets_,
        uint[] memory amountsMax
    ) public view virtual returns (uint[] memory amountsConsumed, uint value) {
        // nosemgrep
        if (assets_.length == 1 && assets_[0] == _getStrategyBaseStorage()._underlying && assets_[0] != address(0)) {
            if (amountsMax.length != 1) {
                revert IControllable.IncorrectArrayLength();
            }
            value = amountsMax[0];
            amountsConsumed = _previewDepositUnderlying(amountsMax[0]);
        } else {
            return _previewDepositAssets(assets_, amountsMax);
        }
    }

    /// @inheritdoc IStrategy
    function previewDepositAssetsWrite(
        address[] memory assets_,
        uint[] memory amountsMax
    ) external virtual returns (uint[] memory amountsConsumed, uint value) {
        // nosemgrep
        if (assets_.length == 1 && assets_[0] == _getStrategyBaseStorage()._underlying && assets_[0] != address(0)) {
            if (amountsMax.length != 1) {
                revert IControllable.IncorrectArrayLength();
            }
            value = amountsMax[0];
            amountsConsumed = _previewDepositUnderlyingWrite(amountsMax[0]);
        } else {
            return _previewDepositAssetsWrite(assets_, amountsMax);
        }
    }

    /// @inheritdoc IStrategy
    function autoCompoundingByUnderlyingProtocol() public view virtual returns (bool) {
        return false;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Default implementations                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Invest underlying asset. Asset must be already on strategy contract balance.
    /// @return Cosumed amounts of invested assets
    function _depositUnderlying(uint /*amount*/ ) internal virtual returns (uint[] memory /*amountsConsumed*/ ) {
        revert(_getStrategyBaseStorage()._underlying == address(0) ? "no underlying" : "not implemented");
    }

    /// @dev Wothdraw underlying invested and send to receiver
    function _withdrawUnderlying(uint, /*amount*/ address /*receiver*/ ) internal virtual {
        revert(_getStrategyBaseStorage()._underlying == address(0) ? "no underlying" : "not implemented");
    }

    /// @dev Calculation of consumed amounts and liquidity/underlying value for provided amount of underlying
    function _previewDepositUnderlying(uint /*amount*/ )
        internal
        view
        virtual
        returns (uint[] memory /*amountsConsumed*/ )
    {}

    function _previewDepositUnderlyingWrite(uint amount)
        internal
        view
        virtual
        returns (uint[] memory amountsConsumed)
    {
        return _previewDepositUnderlying(amount);
    }

    /// @dev Can be overrided by derived base strategies for custom logic
    function _beforeDeposit() internal virtual {}

    /// @dev Can be overrided by derived base strategies for custom logic
    function _beforeWithdraw() internal virtual {}

    /// @dev Can be overrided by derived base strategies for custom logic
    function _beforeTransferAssets() internal virtual {}

    /// @dev Can be overrided by derived base strategies for custom logic
    function _beforeDoHardWork() internal virtual {
        if (!IStrategy(this).isReadyForHardWork()) {
            revert NotReadyForHardWork();
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         Must be implemented by derived contracts           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function supportedVaultTypes() external view virtual returns (string[] memory types);

    /// @dev Investing assets. Amounts must be on strategy contract balance.
    /// @param amounts Amounts of strategy assets to invest
    /// @param claimRevenue Claim revenue before investing
    /// @return value Output of liquidity value or underlying token amount
    function _depositAssets(uint[] memory amounts, bool claimRevenue) internal virtual returns (uint value);

    /// @dev Withdraw assets from investing and send to user.
    /// Here we give the user a choice of assets to withdraw if strategy support it.
    /// This full form of _withdrawAssets can be implemented only in inherited base strategy contract.
    /// @param assets_ Assets for withdrawal. Can contain not all strategy assets if it need.
    /// @param value Part of strategy total value to withdraw
    /// @param receiver User address
    /// @return amountsOut Amounts of assets sent to user
    function _withdrawAssets(
        address[] memory assets_,
        uint value,
        address receiver
    ) internal virtual returns (uint[] memory amountsOut);

    /// @dev Withdraw strategy assets from investing and send to user.
    /// This light form of _withdrawAssets is suitable for implementation into final strategy contract.
    /// @param value Part of strategy total value to withdraw
    /// @param receiver User address
    /// @return amountsOut Amounts of assets sent to user
    function _withdrawAssets(uint value, address receiver) internal virtual returns (uint[] memory amountsOut);

    /// @dev Claim all possible revenue to strategy contract balance and calculate claimed revenue after previous HardWork
    /// @return __assets Strategy assets
    /// @return __amounts Amounts of claimed revenue in form of strategy assets
    /// @return __rewardAssets Farming reward assets
    /// @return __rewardAmounts Amounts of claimed farming rewards
    function _claimRevenue()
        internal
        virtual
        returns (
            address[] memory __assets,
            uint[] memory __amounts,
            address[] memory __rewardAssets,
            uint[] memory __rewardAmounts
        );

    function _processRevenue(
        address[] memory assets_,
        uint[] memory amountsRemaining
    ) internal virtual returns (bool needCompound);

    function _liquidateRewards(
        address exchangeAsset,
        address[] memory rewardAssets_,
        uint[] memory rewardAmounts_
    ) internal virtual returns (uint earnedExchangeAsset);

    /// @dev Reinvest strategy assets of strategy contract balance
    function _compound() internal virtual;

    /// @dev Strategy assets and amounts that strategy invests. Without assets on strategy contract balance
    /// @return assets_ Strategy assets
    /// @return amounts_ Amounts invested
    function _assetsAmounts() internal view virtual returns (address[] memory assets_, uint[] memory amounts_);

    /// @dev Calculation of consumed amounts and liquidity/underlying value for provided strategy assets and amounts.
    /// @dev This full form of _previewDepositAssets can be implemented only in inherited base strategy contract
    /// @param assets_ Strategy assets or part of them, if necessary
    /// @param amountsMax Amounts of specified assets available for investing
    /// @return amountsConsumed Consumed amounts of assets when investing
    /// @return value Liquidity value or underlying token amount minted when investing
    function _previewDepositAssets(
        address[] memory assets_,
        uint[] memory amountsMax
    ) internal view virtual returns (uint[] memory amountsConsumed, uint value);

    /// @dev Write version of _previewDepositAssets
    /// @param assets_ Strategy assets or part of them, if necessary
    /// @param amountsMax Amounts of specified assets available for investing
    /// @return amountsConsumed Consumed amounts of assets when investing
    /// @return value Liquidity value or underlying token amount minted when investing
    function _previewDepositAssetsWrite(
        address[] memory assets_,
        uint[] memory amountsMax
    ) internal virtual returns (uint[] memory amountsConsumed, uint value) {
        return _previewDepositAssets(assets_, amountsMax);
    }

    /// @dev Calculation of consumed amounts and liquidity/underlying value for provided strategy assets and amounts.
    /// Light form of _previewDepositAssets is suitable for implementation into final strategy contract.
    /// @param amountsMax Amounts of specified assets available for investing
    /// @return amountsConsumed Consumed amounts of assets when investing
    /// @return value Liquidity value or underlying token amount minted when investing
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        view
        virtual
        returns (uint[] memory amountsConsumed, uint value);

    /// @dev Write version of _previewDepositAssets
    /// @param amountsMax Amounts of specified assets available for investing
    /// @return amountsConsumed Consumed amounts of assets when investing
    /// @return value Liquidity value or underlying token amount minted when investing
    function _previewDepositAssetsWrite(uint[] memory amountsMax)
        internal
        virtual
        returns (uint[] memory amountsConsumed, uint value)
    {
        return _previewDepositAssets(amountsMax);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getStrategyBaseStorage() internal pure returns (StrategyBaseStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := STRATEGYBASE_STORAGE_LOCATION
        }
    }

    function _requireVault() internal view {
        if (msg.sender != _getStrategyBaseStorage().vault) {
            revert IControllable.NotVault();
        }
    }
}
