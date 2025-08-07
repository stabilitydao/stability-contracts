// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AaveLib} from "./libs/AaveLib.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {IAToken} from "../integrations/aave/IAToken.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IPool} from "../integrations/aave/IPool.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {IVault} from "../interfaces/IVault.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StrategyBase} from "./base/StrategyBase.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {StrategyLib} from "./libs/StrategyLib.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";

/// @title Earns APR by lending assets on AAVE
/// Changelog:
///   1.3.0: Add support of underlying operations - #360
///   1.2.1: Add maxDeploy, use StrategyBase 2.5.0 - #330
///   1.2.0: Add maxWithdrawAsset, poolTvl, aaveToken, use StrategyBase 2.4.0 - #326
///   1.1.0: Use StrategyBase 2.3.0 - add fuseMode
///   1.0.1: fix revenue calculation - #304
/// @author Jude (https://github.com/iammrjude)
/// @author dvpublic (https://github.com/dvpublic)
contract AaveStrategy is StrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.3.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.AaveStrategy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant AAVE_STRATEGY_STORAGE_LOCATION =
        0x86c37fbe4b124a45ab9f98437f581e711a86ea1d20d8d21943d427c270d25e00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.AaveStrategy
    struct AaveStrategyStorage {
        uint lastSharePrice;
        /// @dev Deprecated since 1.3.0, use underlying() instead
        address aToken;
    }

    //region ----------------------- Initialization and restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 3 || nums.length != 0 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }
        address[] memory _assets = new address[](1);
        _assets[0] = IAToken(addresses[2]).UNDERLYING_ASSET_ADDRESS();
        __StrategyBase_init(addresses[0], StrategyIdLib.AAVE, addresses[1], _assets, addresses[2], type(uint).max);
        _getStorage().aToken = addresses[2];

        IERC20(_assets[0]).forceApprove(IAToken(addresses[2]).POOL(), type(uint).max);
    }

    /// @notice Set the underlying asset for the strategy for the case when it wasn't set during initialization
    function setUnderlying() external onlyOperator {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base._underlying = _getStorage().aToken;
    }
    //endregion ----------------------- Initialization and restricted actions

    //region ----------------------- View functions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.AAVE;
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        AaveStrategyStorage storage $ = _getStorage();
        return AaveLib.generateDescription($.aToken);
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        //slither-disable-next-line too-many-digits
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x00d395), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        AaveStrategyStorage storage $ = _getStorage();
        address atoken = $.aToken;
        string memory shortAddr = AaveLib.shortAddress(IAToken(atoken).POOL());
        return (string.concat(IERC20Metadata(atoken).symbol(), " ", shortAddr), true);
    }

    /// @inheritdoc IStrategy
    function supportedVaultTypes() external pure override returns (string[] memory types) {
        types = new string[](1);
        types[0] = VaultTypeLib.COMPOUNDING;
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
        public
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        IFactory.StrategyAvailableInitParams memory params =
            IFactory(IPlatform(platform_).factory()).strategyAvailableInitParams(keccak256(bytes(strategyLogicId())));
        uint len = params.initAddresses.length;
        variants = new string[](len);
        addresses = new address[](len);
        nums = new uint[](0);
        ticks = new int24[](0);
        for (uint i; i < len; ++i) {
            variants[i] = AaveLib.generateDescription(params.initAddresses[i]);
            addresses[i] = params.initAddresses[i];
        }
    }

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function total() public view override returns (uint) {
        AaveStrategyStorage storage $ = _getStorage();
        return StrategyLib.balance($.aToken);
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() external pure override returns (uint[] memory proportions) {
        proportions = new uint[](1);
        proportions[0] = 1e18;
    }

    /// @inheritdoc IStrategy
    function getRevenue() public view override returns (address[] memory assets_, uint[] memory amounts) {
        AaveStrategyStorage storage $ = _getStorage();
        uint newPrice = _getSharePrice($.aToken);
        (assets_, amounts) = _getRevenue(newPrice, $.aToken);
    }

    /// @inheritdoc IStrategy
    function autoCompoundingByUnderlyingProtocol() public pure override returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external pure override returns (bool isReady) {
        isReady = true;
    }

    function aaveToken() external view returns (address) {
        return _getStorage().aToken;
    }

    /// @inheritdoc IStrategy
    function poolTvl() public view override returns (uint tvlUsd) {
        address aToken = _getStorage().aToken;
        address asset = IAToken(aToken).UNDERLYING_ASSET_ADDRESS();

        IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());

        // get price of 1 amount of asset in USD with decimals 18
        // assume that {trusted} value doesn't matter here
        (uint price,) = priceReader.getPrice(asset);

        return IAToken(aToken).totalSupply() * price / (10 ** IERC20Metadata(asset).decimals());
    }

    /// @inheritdoc IStrategy
    function maxWithdrawAssets(uint mode) public view override returns (uint[] memory amounts) {
        address aToken = _getStorage().aToken;
        address asset = IAToken(aToken).UNDERLYING_ASSET_ADDRESS();

        // currently available reserves in the pool
        uint availableLiquidity = IERC20(asset).balanceOf(aToken);

        // aToken balance of the strategy
        uint aTokenBalance = IERC20(aToken).balanceOf(address(this));

        amounts = new uint[](1);
        amounts[0] = mode == 0 ? Math.min(availableLiquidity, aTokenBalance) : aTokenBalance;
    }

    function _previewDepositUnderlying(uint amount) internal pure override returns (uint[] memory amountsConsumed) {
        amountsConsumed = new uint[](1);
        amountsConsumed[0] = amount;
    }
    //endregion ----------------------- View functions

    //region ----------------------- Strategy base
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    //slither-disable-next-line unused-return
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        AaveStrategyStorage storage $ = _getStorage();

        IAToken aToken = IAToken($.aToken);
        address[] memory _assets = assets();

        value = amounts[0];
        if (value != 0) {
            IPool(aToken.POOL()).supply(_assets[0], amounts[0], address(this), 0);

            if ($.lastSharePrice == 0) {
                $.lastSharePrice = _getSharePrice(address(aToken));
            }
        }
    }

    /// @inheritdoc StrategyBase
    function _liquidateRewards(
        address, /*exchangeAsset*/
        address[] memory, /*rewardAssets_*/
        uint[] memory /*rewardAmounts_*/
    ) internal override returns (uint earnedExchangeAsset) {
        // do nothing
    }

    /// @inheritdoc StrategyBase
    function _processRevenue(
        address[] memory, /*assets_*/
        uint[] memory /*amountsRemaining*/
    ) internal override returns (bool needCompound) {
        // do nothing
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
        // do nothing
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        pure
        override
        returns (uint[] memory amountsConsumed, uint value)
    {
        amountsConsumed = new uint[](1);
        amountsConsumed[0] = amountsMax[0];
        value = amountsMax[0];
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(
        address[] memory, /*assets_*/
        uint[] memory amountsMax
    ) internal pure override returns (uint[] memory amountsConsumed, uint value) {
        return _previewDepositAssets(amountsMax);
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();

        return _withdrawAssets($base._assets, value, receiver);
    }

    /// @inheritdoc StrategyBase
    //slither-disable-next-line unused-return
    function _withdrawAssets(
        address[] memory,
        uint value,
        address receiver
    ) internal override returns (uint[] memory amountsOut) {
        amountsOut = new uint[](1);

        AaveStrategyStorage storage $ = _getStorage();
        IAToken aToken = IAToken($.aToken);
        address depositedAsset = aToken.UNDERLYING_ASSET_ADDRESS();

        address[] memory _assets = assets();

        uint initialValue = StrategyLib.balance(depositedAsset);
        IPool(aToken.POOL()).withdraw(_assets[0], value, address(this));
        amountsOut[0] = StrategyLib.balance(depositedAsset) - initialValue;

        IERC20(depositedAsset).safeTransfer(receiver, amountsOut[0]);
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        AaveStrategyStorage storage $ = _getStorage();
        assets_ = $base._assets;
        amounts_ = new uint[](1);
        amounts_[0] = StrategyLib.balance($.aToken);
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
        AaveStrategyStorage storage $ = _getStorage();

        uint newPrice = _getSharePrice($.aToken);
        (__assets, __amounts) = _getRevenue(newPrice, $.aToken);
        $.lastSharePrice = newPrice;

        __rewardAssets = new address[](0);
        __rewardAmounts = new uint[](0);
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(uint amount) internal override returns (uint[] memory amountsConsumed) {
        AaveStrategyStorage storage $ = _getStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();

        amountsConsumed = _previewDepositUnderlying(amount);

        if ($.lastSharePrice == 0) {
            $.lastSharePrice = _getSharePrice($base._underlying);
        }
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        IERC20($base._underlying).safeTransfer(receiver, amount);
    }

    //endregion ----------------------- Strategy base

    //region ----------------------- Internal logic
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function _getStorage() internal pure returns (AaveStrategyStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := AAVE_STRATEGY_STORAGE_LOCATION
        }
    }

    function _getSharePrice(address u) internal view returns (uint) {
        IAToken aToken = IAToken(u);
        uint scaledBalance = aToken.scaledTotalSupply();
        return scaledBalance == 0 ? 0 : aToken.totalSupply() * 1e18 / scaledBalance;
    }

    function _getRevenue(
        uint newPrice,
        address u
    ) internal view returns (address[] memory __assets, uint[] memory amounts) {
        AaveStrategyStorage storage $ = _getStorage();
        __assets = assets();
        amounts = new uint[](1);
        uint oldPrice = $.lastSharePrice;
        if (newPrice > oldPrice && oldPrice != 0) {
            // deposited asset balance
            uint scaledBalance = IAToken(u).scaledBalanceOf(address(this));

            // share price already takes into account accumulated interest
            amounts[0] = scaledBalance * (newPrice - oldPrice) / 1e18;
        }
    }
    //endregion ----------------------- Internal logic
}
