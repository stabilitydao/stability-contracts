// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StrategyBase} from "./base/StrategyBase.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {StrategyLib} from "./libs/StrategyLib.sol";
import {ICErc20Delegate} from "../integrations/mach/ICErc20Delegate.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";

/// @title Earns APR by lending assets on Mach
/// @author Jude (https://github.com/iammrjude)
contract MachStrategy is StrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.MachStrategy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant MACH_STRATEGY_STORAGE_LOCATION =
        0x9a791f9a94b094c65f0426a773fcb8c8d495b537b4f39c7682948f62440f1e00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.MachStrategy
    struct MachStrategyStorage {
        uint lastSharePrice;
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
        _assets[0] = ICErc20Delegate(addresses[2]).underlying();
        __StrategyBase_init(addresses[0], StrategyIdLib.MACH, addresses[1], _assets, addresses[2], type(uint).max);

        IERC20(_assets[0]).forceApprove(addresses[2], type(uint).max); // TODO: approve CErc20Delegate (_underlying) to spend asset (_assets[0])
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.MACH;
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
        return (IERC20Metadata($base._underlying).symbol(), true); // TODO
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
        address u = $base._underlying;
        uint newSharePrice = _getSharePrice(u); // TODO
        (assets_, amounts) = _getRevenue(newSharePrice, u); // TODO
    }

    /// @inheritdoc IStrategy
    function autoCompoundingByUnderlyingProtocol() public pure override returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external pure override returns (bool isReady) {
        // (address[] memory __assets, uint[] memory amounts) = getRevenue();
        // isReady = amounts[0] > ISwapper(IPlatform(platform()).swapper()).threshold(__assets[0]);
        isReady = true; // TODO
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    //slither-disable-next-line unused-return
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        MachStrategyStorage storage $ = _getStorage();

        address u = $base._underlying;
        ICErc20Delegate cToken = ICErc20Delegate(u);
        uint initialValue = StrategyLib.balance(address(cToken));
        uint success = cToken.mintAsCollateral(amounts[0]);
        if (success == 0) value = StrategyLib.balance(address(cToken)) - initialValue;

        if ($.lastSharePrice == 0) {
            $.lastSharePrice = _getSharePrice(u);
        }
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(uint amount) internal override returns (uint[] memory amountsConsumed) {
        amountsConsumed = new uint[](1);
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        address u = $base._underlying;
        amountsConsumed[0] = (amount * ICErc20Delegate(u).exchangeRateStored()) / 1e18; // TODO
        MachStrategyStorage storage $ = _getStorage();
        if ($.lastSharePrice == 0) {
            $.lastSharePrice = _getSharePrice(u);
        }
    }

    /// @inheritdoc StrategyBase
    function _liquidateRewards(
        address exchangeAsset,
        address[] memory rewardAssets_,
        uint[] memory rewardAmounts_
    ) internal override returns (uint earnedExchangeAsset) {}

    /// @inheritdoc StrategyBase
    function _processRevenue(
        address[] memory assets_,
        uint[] memory amountsRemaining
    ) internal override returns (bool needCompound) {}

    /// @inheritdoc StrategyBase
    function _compound() internal override {}

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        view
        override
        returns (uint[] memory amountsConsumed, uint value)
    {
        amountsConsumed = new uint[](1);
        amountsConsumed[0] = amountsMax[0];
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        value = (amountsMax[0] * 1e18) / ICErc20Delegate($base._underlying).exchangeRateStored(); // TODO
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(
        address[] memory, /*assets_*/
        uint[] memory amountsMax
    ) internal view override returns (uint[] memory amountsConsumed, uint value) {
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
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        ICErc20Delegate cToken = ICErc20Delegate($base._underlying);
        address depositedAsset = cToken.underlying();
        uint initialValue = StrategyLib.balance(depositedAsset);
        uint success = cToken.redeem(value);
        uint amountOut = StrategyLib.balance(depositedAsset) - initialValue;
        if (success == 0) amountsOut[0] = amountOut;

        IERC20(depositedAsset).safeTransfer(receiver, amountOut);
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        IERC20($base._underlying).safeTransfer(receiver, amount);
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        assets_ = $base._assets;
        address u = $base._underlying;
        amounts_ = new uint[](1);
        amounts_[0] = (StrategyLib.balance(u) * ICErc20Delegate(u).exchangeRateStored()) / 1e18; // TODO
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
        MachStrategyStorage storage $ = _getStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        address u = $base._underlying;
        uint newSharePrice = _getSharePrice(u);
        (__assets, __amounts) = _getRevenue(newSharePrice, u); // TODO
        $.lastSharePrice = newSharePrice;
        __rewardAssets = new address[](0);
        __rewardAmounts = new uint[](0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _generateDescription(address cToken) internal view returns (string memory) {
        // TODO
        //slither-disable-next-line calls-loop
        return string.concat(
            "Earn",
            " and supply APR by lending ",
            IERC20Metadata(ICErc20Delegate(cToken).underlying()).symbol(),
            " to Mach "
        );
    }

    function _getStorage() internal pure returns (MachStrategyStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := MACH_STRATEGY_STORAGE_LOCATION
        }
    }

    // TODO
    function _getSharePrice(address u) internal view returns (uint) {
        // totalSupply cant be zero in our integrations
        return ICErc20Delegate(u).totalReserves() * 1e18 / ICErc20Delegate(u).totalSupply();
    }

    // TODO
    function _getRevenue(
        uint newSharePrice,
        address u
    ) internal view returns (address[] memory __assets, uint[] memory amounts) {
        MachStrategyStorage storage $ = _getStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        __assets = $base._assets;
        amounts = new uint[](1);
        uint oldSharePrice = $.lastSharePrice;
        // nosemgrep
        if (newSharePrice > oldSharePrice && oldSharePrice != 0) {
            // TODO: this calculation might not be correct
            amounts[0] = StrategyLib.balance(u) * newSharePrice * (newSharePrice - oldSharePrice) / oldSharePrice / 1e18;
        }
    }
}
