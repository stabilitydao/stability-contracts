// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../lib/forge-std/src/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StrategyBase} from "./base/StrategyBase.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {StrategyLib} from "./libs/StrategyLib.sol";
import {IAToken} from "../integrations/aave/IAToken.sol";
import {IPool} from "../integrations/aave/IPool.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";

/// @title Earns APR by lending assets on Vicuna
/// @author Jude (https://github.com/iammrjude)
/// @author dvpublic (https://github.com/dvpublic)
contract AaveStrategy is StrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.VicunaStrategy")) - 1)) & ~bytes32(uint256(0xff));  // todo replace address on AaveStrategy
    bytes32 private constant AAVE_STRATEGY_STORAGE_LOCATION =
        0x530695c2eafb127614949cc2e09f1e64f3538a3c09bfb455b925ddc34c079500; // todo update address

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.VicunaStrategy // todo replace by AaveStrategy
    struct AaveStrategyStorage {
        uint initialDeposit; // todo remove
        /// @notice Last CVault.price()
        uint lastPrice;
    }

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

        IERC20(_assets[0]).forceApprove(IAToken(addresses[2]).POOL(), type(uint).max);
    }

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
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        return _generateDescription($base._underlying);
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        //slither-disable-next-line too-many-digits
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x00d395), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        return (IERC20Metadata($base._underlying).symbol(), true);
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
            variants[i] = _generateDescription(params.initAddresses[i]);
            addresses[i] = params.initAddresses[i];
        }
    }

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function total() public view override returns (uint) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        return StrategyLib.balance($base._underlying);
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() external pure override returns (uint[] memory proportions) {
        proportions = new uint[](1);
        proportions[0] = 1e18;
    }

    /// @inheritdoc IStrategy
    function getRevenue() public view override returns (address[] memory assets_, uint[] memory amounts) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        (uint newPrice,) = IVault($base.vault).price();
        (assets_, amounts) = _getRevenue(newPrice, $base._underlying);
    }

    /// @inheritdoc IStrategy
    function autoCompoundingByUnderlyingProtocol() public pure override returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external pure override returns (bool isReady) {
        isReady = true;
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
        console.log("_depositAssets.amount", amounts[0]);
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();

        IAToken aToken = IAToken($base._underlying);
        address[] memory _assets = assets();

        uint initialValue = StrategyLib.balance(address(aToken));
        IPool(aToken.POOL()).supply(_assets[0], amounts[0], address(this), 0);
        value = StrategyLib.balance(address(aToken)) - initialValue;

        console.log("_depositAssets.initialValue", initialValue);
        console.log("_depositAssets.value", value);
        console.log("_depositAssets.lastPrice.before", $.lastPrice);

        if ($.lastPrice == 0) {
            ($.lastPrice,) = IVault($base.vault).price();
        }
        console.log("_depositAssets.lastPrice.after", $.lastPrice);
    }

//    /// @inheritdoc StrategyBase
//    function _depositUnderlying(uint amount) internal pure override returns (uint[] memory amountsConsumed) {
//        console.log("_depositUnderlying.amount", amount);
//        amountsConsumed = new uint[](1);
//        amountsConsumed[0] = amount; // todo why the function is not implemented?
//    }

    /// @inheritdoc StrategyBase
    function _liquidateRewards(
        address /*exchangeAsset*/,
        address[] memory /*rewardAssets_*/,
        uint[] memory /*rewardAmounts_*/
    ) internal override returns (uint earnedExchangeAsset) {
        // do nothing
    }

    /// @inheritdoc StrategyBase
    function _processRevenue(
        address[] memory /*assets_*/,
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
        console.log("_withdrawAssets.value", value);
        console.log("_withdrawAssets.receiver", receiver);
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
        console.log("_withdrawAssets.internal", value, receiver);
        amountsOut = new uint[](1);

        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        IAToken aToken = IAToken($base._underlying);
        address depositedAsset = aToken.UNDERLYING_ASSET_ADDRESS(); // todo can we use assets[0] instead?

        address[] memory _assets = assets();

        uint initialValue = StrategyLib.balance(depositedAsset);
        IPool(aToken.POOL()).withdraw(_assets[0], value, address(this));
        uint amountOut = StrategyLib.balance(depositedAsset) - initialValue;

        amountsOut[0] = amountOut;

        console.log("_withdrawAssets.depositedAsset", depositedAsset);
        console.log("_withdrawAssets.initialValue", initialValue);
        console.log("_withdrawAssets._assets", _assets[0]);
        console.log("_withdrawAssets.amountOut", amountOut);

        IERC20(depositedAsset).safeTransfer(receiver, amountOut);
        console.log("_withdrawAssets.safeTransfer", amountOut);
    }

//    /// @inheritdoc StrategyBase
//    function _withdrawUnderlying(uint amount, address receiver) internal override {
//        console.log("_withdrawAssets._withdrawUnderlying", amount, receiver);
//        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
//        IERC20($base._underlying).safeTransfer(receiver, amount);
//    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        assets_ = $base._assets;
        amounts_ = new uint[](1);
        amounts_[0] = StrategyLib.balance($base._underlying);
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
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        AaveStrategyStorage storage $ = _getStorage();

        (uint newPrice,) = IVault($base.vault).price();
        (__assets, __amounts) = _getRevenue(newPrice, $base._underlying);
        $.lastPrice = newPrice;

        __rewardAssets = new address[](0);
        __rewardAmounts = new uint[](0);
    }
    //endregion ----------------------- Strategy base

    //region ----------------------- Internal logic
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _generateDescription(address aToken) internal view returns (string memory) {
        //slither-disable-next-line calls-loop
        return
            string.concat("Supply ", IERC20Metadata(IAToken(aToken).UNDERLYING_ASSET_ADDRESS()).symbol(), " to Vicuna ");
    }

    function _getRevenue(uint newPrice, address u) internal view returns (address[] memory __assets, uint[] memory amounts) {
        AaveStrategyStorage storage $ = _getStorage();
        __assets = assets();
        amounts = new uint[](1);
        uint oldPrice = $.lastPrice;
        if (newPrice > oldPrice && oldPrice != 0) {
            amounts[0] = StrategyLib.balance(u) * newPrice * (newPrice - oldPrice) / oldPrice;
        }

        console.log("_getRevenue", amounts[0]);
    }

    function _getStorage() internal pure returns (AaveStrategyStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := AAVE_STRATEGY_STORAGE_LOCATION
        }
    }
    //endregion ----------------------- Internal logic
}
