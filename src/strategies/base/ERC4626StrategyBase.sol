// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "./StrategyBase.sol";

/// @notice Hold ERC4626 vault shares, emit APR and collect fees
/// @author Alien Deployer (https://github.com/a17)
abstract contract ERC4626StrategyBase is StrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of ERC4626StrategyBase implementation
    string public constant VERSION_ERC4626_STRATEGY_BASE = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.ERC4626StrategyBase")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant ERC4626_STRATEGY_BASE_STORAGE_LOCATION =
        0x5b77806ff180dee2d0be2cd23be20d60541fe5fbef60bd0f3013af3027492200;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.ERC4626StrategyBase
    struct ERC4626StrategyBaseStorage {
        uint lastSharePrice;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    //slither-disable-next-line naming-convention
    function __ERC4626StrategyBase_init(
        string memory id,
        address platform_,
        address vault_,
        address underlying_
    ) internal onlyInitializing {
        address[] memory _assets = new address[](1);
        _assets[0] = IERC4626(underlying_).asset();
        //slither-disable-next-line reentrancy-events
        __StrategyBase_init(platform_, id, vault_, _assets, underlying_, type(uint).max);
        IERC20(_assets[0]).forceApprove(underlying_, type(uint).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function supportedVaultTypes() external view virtual override returns (string[] memory types) {
        types = new string[](1);
        types[0] = VaultTypeLib.COMPOUNDING;
    }

    /// @inheritdoc IStrategy
    function total() public view override returns (uint) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        return StrategyLib.balance(__$__._underlying);
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() public pure returns (uint[] memory proportions) {
        proportions = new uint[](1);
        proportions[0] = 1e18;
    }

    /// @inheritdoc IStrategy
    function getRevenue() public view returns (address[] memory __assets, uint[] memory amounts) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        address u = __$__._underlying;
        uint newSharePrice = _getSharePrice(u);
        (__assets, amounts) = _getRevenue(newSharePrice, u);
    }

    /// @inheritdoc IStrategy
    function autoCompoundingByUnderlyingProtocol() public view virtual override returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external view virtual returns (bool isReady) {
        (address[] memory __assets, uint[] memory amounts) = getRevenue();
        isReady = amounts[0] > ISwapper(IPlatform(platform()).swapper()).threshold(__assets[0]);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        address u = $base._underlying;
        value = IERC4626(u).deposit(amounts[0], address(this));
        ERC4626StrategyBaseStorage storage $ = _getERC4626StrategyBaseStorage();
        if ($.lastSharePrice == 0) {
            $.lastSharePrice = _getSharePrice(u);
        }
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(uint amount) internal override returns (uint[] memory amountsConsumed) {
        amountsConsumed = new uint[](1);
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        address u = $base._underlying;
        amountsConsumed[0] = IERC4626(u).convertToAssets(amount);
        ERC4626StrategyBaseStorage storage $ = _getERC4626StrategyBaseStorage();
        if ($.lastSharePrice == 0) {
            $.lastSharePrice = _getSharePrice(u);
        }
    }

    function _liquidateRewards(
        address, /*exchangeAsset*/
        address[] memory, /*rewardAssets_*/
        uint[] memory /*rewardAmounts_*/
    ) internal pure override returns (uint earnedExchangeAsset) {
        // do nothing
    }

    /// @inheritdoc StrategyBase
    function _processRevenue(
        address[] memory, /*assets_*/
        uint[] memory /*amountsRemaining*/
    ) internal pure override returns (bool needCompound) {
        // do nothing
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
        // do nothing
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        view
        override(StrategyBase)
        returns (uint[] memory amountsConsumed, uint value)
    {
        amountsConsumed = new uint[](1);
        amountsConsumed[0] = amountsMax[0];
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        value = IERC4626(__$__._underlying).convertToShares(amountsMax[0]);
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(
        address[] memory, /*assets_*/
        uint[] memory amountsMax
    ) internal view override(StrategyBase) returns (uint[] memory amountsConsumed, uint value) {
        return _previewDepositAssets(amountsMax);
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        StrategyBaseStorage storage _$_ = _getStrategyBaseStorage();
        return _withdrawAssets(_$_._assets, value, receiver);
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(
        address[] memory,
        uint value,
        address receiver
    ) internal override returns (uint[] memory amountsOut) {
        amountsOut = new uint[](1);
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        amountsOut[0] = IERC4626(__$__._underlying).redeem(value, receiver, address(this));
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        IERC20(__$__._underlying).safeTransfer(receiver, amount);
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        assets_ = __$__._assets;
        address u = __$__._underlying;
        amounts_ = new uint[](1);
        amounts_[0] = IERC4626(u).convertToAssets(IERC20(u).balanceOf(address(this)));
    }

    /// @inheritdoc StrategyBase
    function _claimRevenue()
        internal
        override
        returns (
            address[] memory __assets,
            uint[] memory __amounts,
            address[] memory __rewardAssets,
            uint[] memory __rewardAmounts
        )
    {
        ERC4626StrategyBaseStorage storage $ = _getERC4626StrategyBaseStorage();
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        address u = __$__._underlying;
        uint newSharePrice = _getSharePrice(u);
        (__assets, __amounts) = _getRevenue(newSharePrice, u);
        $.lastSharePrice = newSharePrice;
        __rewardAssets = new address[](0);
        __rewardAmounts = new uint[](0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getERC4626StrategyBaseStorage() internal pure returns (ERC4626StrategyBaseStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := ERC4626_STRATEGY_BASE_STORAGE_LOCATION
        }
    }

    function _getSharePrice(address u) internal view returns (uint) {
        // totalSupply cant be zero in our integrations
        return IERC4626(u).totalAssets() * 1e18 / IERC4626(u).totalSupply();
    }

    function _getRevenue(
        uint newSharePrice,
        address u
    ) internal view returns (address[] memory __assets, uint[] memory amounts) {
        ERC4626StrategyBaseStorage storage $ = _getERC4626StrategyBaseStorage();
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        __assets = __$__._assets;
        amounts = new uint[](1);
        uint oldSharePrice = $.lastSharePrice;
        // nosemgrep
        if (newSharePrice > oldSharePrice && oldSharePrice != 0) {
            amounts[0] = StrategyLib.balance(u) * newSharePrice * (newSharePrice - oldSharePrice) / oldSharePrice / 1e18;
        }
    }
}
