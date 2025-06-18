// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {StrategyBase} from "./StrategyBase.sol";
import {VaultTypeLib} from "../../core/libs/VaultTypeLib.sol";
import {CommonLib} from "../../core/libs/CommonLib.sol";
import {ILeverageLendingStrategy} from "../../interfaces/ILeverageLendingStrategy.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {IHardWorker} from "../../interfaces/IHardWorker.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IControllable} from "../../interfaces/IControllable.sol";

/// @notice Base strategy for leverage lending
/// Changelog:
///   1.2.2: add universalAddress1 and withdrawParam2 to universal params
///   1.2.1: rebalanceDebt reverts if result share price less #277
///   1.2.0: feat: return new share price by rebalanceDebt #256; feat: use BeetsV3 OR UniswapV3-like DeX free flash loans #268
///   1.1.1: StrategyBase 2.1.3
///   1.1.0: targetLeveragePercent setup in strategy initializer; 8 universal configurable params
/// @author Alien Deployer (https://github.com/a17)
/// @author dvpublic (https://github.com/dvpublic)
abstract contract LeverageLendingBase is StrategyBase, ILeverageLendingStrategy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of FarmingStrategyBase implementation
    string public constant VERSION_LEVERAGE_LENDING_STRATEGY_BASE = "1.2.2";

    /// @dev 100_00 is 1.0 or 100%
    uint internal constant INTERNAL_PRECISION = 100_00;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.LeverageLendingBase")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant LEVERAGE_LENDING_STRATEGY_STORAGE_LOCATION =
        0xbcea52cc71723df4e8ce4341004b27df2cc7bc9197584ea7d92bbe219528f700;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    //slither-disable-next-line naming-convention
    function __LeverageLendingBase_init(LeverageLendingStrategyBaseInitParams memory params)
        internal
        onlyInitializing
    {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        $.collateralAsset = params.collateralAsset;
        $.borrowAsset = params.borrowAsset;
        $.lendingVault = params.lendingVault;
        $.borrowingVault = params.borrowingVault;
        $.flashLoanVault = params.flashLoanVault;
        $.helper = params.helper;
        $.targetLeveragePercent = params.targetLeveragePercent;
        emit TargetLeveragePercent(params.targetLeveragePercent);
        address[] memory _assets = new address[](1);
        _assets[0] = params.collateralAsset;
        __StrategyBase_init(params.platform, params.strategyId, params.vault, _assets, address(0), type(uint).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc ILeverageLendingStrategy
    function rebalanceDebt(uint newLtv, uint minSharePrice) external returns (uint resultLtv, uint resultSharePrice) {
        IPlatform _platform = IPlatform(platform());
        IHardWorker hardworker = IHardWorker(_platform.hardWorker());
        address rebalancer = _platform.rebalancer();
        if (
            msg.sender != rebalancer && !_platform.isOperator(msg.sender)
                && !hardworker.dedicatedServerMsgSender(msg.sender)
        ) {
            revert IControllable.IncorrectMsgSender();
        }

        resultLtv = _rebalanceDebt(newLtv);
        (resultSharePrice,) = _realSharePrice();
        require(resultSharePrice >= minSharePrice, IControllable.TooLowValue(resultSharePrice));
    }

    /// @inheritdoc ILeverageLendingStrategy
    function realSharePrice() external view returns (uint sharePrice, bool trusted) {
        return _realSharePrice();
    }

    /// @inheritdoc ILeverageLendingStrategy
    function setTargetLeveragePercent(uint value) external onlyOperator {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        $.targetLeveragePercent = value;
        emit TargetLeveragePercent(value);
    }

    /// @inheritdoc ILeverageLendingStrategy
    function setUniversalParams(uint[] memory params, address[] memory addresses) external onlyOperator {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        $.depositParam0 = params[0];
        $.depositParam1 = params[1];
        $.withdrawParam0 = params[2];
        $.withdrawParam1 = params[3];
        $.increaseLtvParam0 = params[4];
        $.increaseLtvParam1 = params[5];
        $.decreaseLtvParam0 = params[6];
        $.decreaseLtvParam1 = params[7];
        $.swapPriceImpactTolerance0 = params[8];
        $.swapPriceImpactTolerance1 = params[9];
        $.flashLoanKind = params[10];
        $.withdrawParam2 = params[11];

        $.flashLoanVault = addresses[0];
        $.universalAddress1 = addresses[1];

        emit UniversalParams(params);
        emit UniversalAddresses(addresses);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(ILeverageLendingStrategy).interfaceId || super.supportsInterface(interfaceId);
    }

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

    /// @inheritdoc IStrategy
    function autoCompoundingByUnderlyingProtocol() public view virtual override returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function getRevenue() external pure virtual returns (address[] memory assets_, uint[] memory amounts) {}

    /// @inheritdoc ILeverageLendingStrategy
    function getUniversalParams() external view returns (uint[] memory params, address[] memory addresses) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        params = new uint[](12);
        params[0] = $.depositParam0;
        params[1] = $.depositParam1;
        params[2] = $.withdrawParam0;
        params[3] = $.withdrawParam1;
        params[4] = $.increaseLtvParam0;
        params[5] = $.increaseLtvParam1;
        params[6] = $.decreaseLtvParam0;
        params[7] = $.decreaseLtvParam1;
        params[8] = $.swapPriceImpactTolerance0;
        params[9] = $.swapPriceImpactTolerance1;
        params[10] = $.flashLoanKind;
        params[11] = $.withdrawParam2;

        addresses = new address[](2);
        addresses[0] = $.flashLoanVault;
        addresses[1] = $.universalAddress1;
    }
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _compound() internal virtual override {}

    /// @inheritdoc StrategyBase
    function _processRevenue(
        address[] memory, /*assets_*/
        uint[] memory /*amountsRemaining*/
    ) internal pure virtual override returns (bool needCompound) {
        needCompound = true;
    }

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
    ) internal virtual override returns (uint earnedExchangeAsset) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         Must be implemented by derived contracts           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _rebalanceDebt(uint newLtv) internal virtual returns (uint resultLtv);

    function _realSharePrice() internal view virtual returns (uint sharePrice, bool trusted);

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
