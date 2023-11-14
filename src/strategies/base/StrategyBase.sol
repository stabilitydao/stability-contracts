// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../core/base/Controllable.sol";
import "../../core/libs/VaultTypeLib.sol";
import "../libs/StrategyLib.sol";
import "../../interfaces/IStrategy.sol";
import "../../interfaces/IVault.sol";

/// @dev Base universal strategy
/// @author Alien Deployer (https://github.com/a17)
abstract contract StrategyBase is Controllable, IStrategy {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    /// @dev Version of StrategyBase implementation
    string public constant VERSION_STRATEGY_BASE = '1.0.0';

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error BadInitParams();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    address public vault;

    /// @inheritdoc IStrategy
    uint public total;

    /// @inheritdoc IStrategy
    uint public lastHardWork;

    /// @inheritdoc IStrategy
    uint public lastApr;

    /// @inheritdoc IStrategy
    uint public lastAprCompound;

    string internal _id;
    address[] internal _assets;
    address internal _underlying;
    uint internal _exchangeAssetIndex;

    /// @dev This empty reserved space is put in place to allow future versions to add new.
    /// variables without shifting down storage in the inheritance chain.
    /// Total gap == 50 - storage slots used.
    uint[50 - 9] private __gap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function __StrategyBase_init(
        address platform_,
        string memory id_,
        address vault_,
        address[] memory assets_,
        address underlying_,
        uint exchangeAssetIndex_
    ) internal onlyInitializing {
        __Controllable_init(platform_);
        (_id, vault, _assets, _underlying, _exchangeAssetIndex) = (id_, vault_, assets_, underlying_, exchangeAssetIndex_);
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
        if (lastHardWork == 0) {
            lastHardWork = block.timestamp;
        }
        return _depositAssets(amounts, true);
    }

    /// @inheritdoc IStrategy
    function withdrawAssets(address[] memory assets_, uint value, address receiver) external virtual onlyVault returns (uint[] memory amountsOut) {
        return _withdrawAssets(assets_, value, receiver);
    }

    function depositUnderlying(uint amount) external virtual override onlyVault returns(uint[] memory amountsConsumed) {
        return _depositUnderlying(amount);
    }

    function withdrawUnderlying(uint amount, address receiver) external virtual override onlyVault {
        _withdrawUnderlying(amount, receiver);
    }

    /// @inheritdoc IStrategy
    function transferAssets(uint amount, uint total_, address receiver) external onlyVault returns (uint[] memory amountsOut) {
        //slither-disable-next-line unused-return
        return StrategyLib.transferAssets(_assets, amount, total_, receiver);
    }

    function doHardWork() external onlyVault {
        address _vault = vault;
        //slither-disable-next-line unused-return
        (uint tvl,) = IVault(_vault).tvl();
        if (tvl > 0) {
            address _platform = platform();
            uint exchangeAssetIndex = _exchangeAssetIndex;

            (
                address[] memory __assets,
                uint[] memory __amounts,
                address[] memory __rewardAssets,
                uint[] memory __rewardAmounts
            ) = _claimRevenue();

            __amounts[exchangeAssetIndex] += _liquidateRewards(__assets[exchangeAssetIndex], __rewardAssets, __rewardAmounts);

            uint[] memory amountsRemaining = StrategyLib.extractFees(_platform, _vault, _id, __assets, __amounts);

            bool needCompound = _processRevenue(__assets, amountsRemaining);

            uint totalBefore = total;

            if (needCompound) {
                _compound();
            }

            (lastApr, lastAprCompound) = StrategyLib.emitApr(lastHardWork, _platform, __assets, __amounts, tvl, totalBefore, total, vault);
            lastHardWork = block.timestamp;
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override (Controllable, IERC165) returns (bool) {
        return 
            interfaceId == type(IStrategy).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function STRATEGY_LOGIC_ID() public view virtual returns(string memory);

    function assets() external virtual view returns (address[] memory) {
        return _assets;
    }

    /// @inheritdoc IStrategy
    function underlying() external view override returns (address) {
        return _underlying;
    }

    /// @inheritdoc IStrategy
    function assetsAmounts() external view virtual returns (address[] memory assets_, uint[] memory amounts_) {
        (assets_, amounts_) = _assetsAmounts();
        return StrategyLib.assetsAmountsWithBalances(assets_, amounts_);
    }

    /// @inheritdoc IStrategy
    function previewDepositAssets(address[] memory assets_, uint[] memory amountsMax) external view virtual returns (uint[] memory amountsConsumed, uint value) {
        if (assets_.length == 1 && assets_[0] == _underlying && assets_[0] != address(0)) {
            require(amountsMax.length == 1, "StrategyBase: incorrect length");
            value = amountsMax[0];
            amountsConsumed = _previewDepositUnderlying(amountsMax[0]);
        } else {
            return _previewDepositAssets(assets_, amountsMax);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Default implementations                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function getSpecificName() external view virtual returns (string memory) {
        return "";
    }

    /// @dev Invest underlying asset. Asset must be already on strategy contract balance.
    /// @return Cosumed amounts of invested assets
    function _depositUnderlying(uint /*amount*/) internal virtual returns(uint[] memory /*amountsConsumed*/) {
        revert(_underlying == address(0) ? 'no underlying' : 'not implemented');
    }

    /// @dev Wothdraw underlying invested and send to receiver
    function _withdrawUnderlying(uint /*amount*/, address /*receiver*/) internal virtual {
        revert(_underlying == address(0) ? 'no underlying' : 'not implemented');
    }

    /// @dev Calculation of consumed amounts and liquidity/underlying value for provided amount of underlying
    function _previewDepositUnderlying(uint /*amount*/) internal view virtual returns(uint[] memory /*amountsConsumed*/) {
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         Must be implemented by derived contracts           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function supportedVaultTypes() external view virtual returns(string[] memory types);

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
    function _withdrawAssets(address[] memory assets_, uint value, address receiver) internal virtual returns (uint[] memory amountsOut);

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
    function _claimRevenue() internal virtual returns (address[] memory __assets, uint[] memory __amounts, address[] memory __rewardAssets, uint[] memory __rewardAmounts);

    function _processRevenue(address[] memory assets_, uint[] memory amountsRemaining) internal virtual returns (bool needCompound);

    function _liquidateRewards(address exchangeAsset, address[] memory rewardAssets_, uint[] memory rewardAmounts_) internal virtual returns (uint earnedExchangeAsset);

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
    /// @return amountsConsumed Cosumed amounts of assets when investing
    /// @return value Liquidity value or underlying token amount minted when investing
    function _previewDepositAssets(address[] memory assets_, uint[] memory amountsMax) internal view virtual returns (uint[] memory amountsConsumed, uint value);

    /// @dev Calculation of consumed amounts and liquidity/underlying value for provided strategy assets and amounts.
    /// Light form of _previewDepositAssets is suitable for implementation into final strategy contract.
    /// @param amountsMax Amounts of specified assets available for investing
    /// @return amountsConsumed Cosumed amounts of assets when investing
    /// @return value Liquidity value or underlying token amount minted when investing
    function _previewDepositAssets(uint[] memory amountsMax) internal view virtual returns (uint[] memory amountsConsumed, uint value);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _requireVault() internal view {
        require(msg.sender == vault, "StrategyBase: not vault");
    }

    function _balance(address token) internal view returns (uint) {
        return IERC20(token).balanceOf(address(this));
    }
}
