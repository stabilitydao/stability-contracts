// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {StrategyBase} from "./StrategyBase.sol";
import {VaultTypeLib} from "../../core/libs/VaultTypeLib.sol";
import {CommonLib} from "../../core/libs/CommonLib.sol";
import {ILeverageLendingStrategy} from "../../interfaces/ILeverageLendingStrategy.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";

abstract contract LeverageLendingBase is StrategyBase, ILeverageLendingStrategy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of FarmingStrategyBase implementation
    string public constant VERSION_LEVERAGE_LENDING_STRATEGY_BASE = "1.0.0";

    // todo
    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.LeverageLendingBase")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant LEVERAGE_LENDING_STRATEGY_STORAGE_LOCATION =
        0xe61f0a7b2953b9e28e48cc07562ad7979478dcaee972e68dcf3b10da2cba6000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    //slither-disable-next-line naming-convention
    function __LeverageLendingBase_init(
        string memory id,
        address platform_,
        address vault_,
        address collateralAsset_,
        address borrowAsset_,
        address lendingVault_,
        address borrowingVault_
    ) internal onlyInitializing {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        $.collateralAsset = collateralAsset_;
        $.borrowAsset = borrowAsset_;
        $.lendingVault = lendingVault_;
        $.borrowingVault = borrowingVault_;
        address[] memory _assets = new address[](1);
        _assets[0] = collateralAsset_;
        __StrategyBase_init(platform_, id, vault_, _assets, address(0), type(uint).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function supportedVaultTypes() external view virtual override returns (string[] memory types) {
        types = new string[](1);
        types[0] = VaultTypeLib.COMPOUNDING;
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() public pure returns (uint[] memory proportions) {
        proportions = new uint[](1);
        proportions[0] = 1e18;
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external pure virtual returns (bool isReady) {
        return true;
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        //slither-disable-next-line too-many-digits
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0xffffff), bytes3(0x000000)));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(
        address[] memory, /*assets_*/
        uint[] memory amountsMax
    ) internal view override(StrategyBase) returns (uint[] memory amountsConsumed, uint value) {
        return _previewDepositAssets(amountsMax);
    }

    function _withdrawAssets(
        address[] memory, /*assets_*/
        uint value,
        address receiver
    ) internal virtual override returns (uint[] memory amountsOut) {
        return _withdrawAssets(value, receiver);
    }

    /// @inheritdoc StrategyBase
    function _liquidateRewards(
        address exchangeAsset,
        address[] memory rewardAssets_,
        uint[] memory rewardAmounts_
    ) internal override returns (uint earnedExchangeAsset) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getLeverageLendingBaseStorage() internal pure returns (LeverageLendingBaseStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := LEVERAGE_LENDING_STRATEGY_STORAGE_LOCATION
        }
    }
}
