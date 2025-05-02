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
///   1.1.2 #256 rebalanceDebt returns resultSharePrice; #268: add flashLoanKind and setFlashLoanVault
///   1.1.1: StrategyBase 2.1.3
///   1.1.0: targetLeveragePercent setup in strategy initializer; 8 universal configurable params
/// @author Alien Deployer (https://github.com/a17)
abstract contract LeverageLendingBase is StrategyBase, ILeverageLendingStrategy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of FarmingStrategyBase implementation
    string public constant VERSION_LEVERAGE_LENDING_STRATEGY_BASE = "1.1.2";

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
    function rebalanceDebt(uint newLtv) external returns (uint resultLtv, uint resultSharePrice) {
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
        (resultSharePrice, ) = _realSharePrice();
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
    function setUniversalParams(uint[] memory params) external onlyOperator {
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
        emit UniversalParams(params);
    }

    /// @notice Set flash loan vault
    /// @param flashLoanVault_ Adress of the new vault
    /// @param flashLoanKind Kind of the new vault: see FLASH_LOAN_KIND_BALANCER_V2
    function setFlashLoanVault(address flashLoanVault_, uint flashLoanKind) external onlyOperator {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        $.flashLoanVault = flashLoanVault_;
        $.flashLoanKind = flashLoanKind;
        emit ChangeFlashLoanVault(flashLoanVault_);
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
    ) internal override returns (uint earnedExchangeAsset) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         Must be implemented by derived contracts           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _rebalanceDebt(uint newLtv) internal virtual returns (uint resultLtv);

    function _realSharePrice() internal virtual view returns (uint sharePrice, bool trusted);

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
