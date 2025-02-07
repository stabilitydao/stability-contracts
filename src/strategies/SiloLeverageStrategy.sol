// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {StrategyBase} from "./base/StrategyBase.sol";
import {LeverageLendingBase} from "./base/LeverageLendingBase.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";

contract SiloLeverage is LeverageLendingBase {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 4 || nums.length != 0 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }

        address collateralAsset = IERC4626(addresses[2]).asset();

        __LeverageLendingBase_init(
            StrategyIdLib.SILO_LEVERAGE,
            addresses[0],
            addresses[1],
            collateralAsset,
            IERC4626(addresses[3]).asset(),
            addresses[2],
            addresses[3]
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.SILO_LEVERAGE;
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
        public
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        IFactory.StrategyAvailableInitParams memory params =
            IFactory(IPlatform(platform_).factory()).strategyAvailableInitParams(keccak256(bytes(strategyLogicId())));
        uint len = params.initNums[0];
        variants = new string[](len);
        addresses = new address[](len * 2);
        nums = new uint[](0);
        ticks = new int24[](0);
        for (uint i; i < len; ++i) {
            address collateralAsset = IERC4626(params.initAddresses[i * 2]).asset();
            address borrowAsset = IERC4626(params.initAddresses[i * 2 + 1]).asset();
            variants[i] = _generateDescription(collateralAsset, borrowAsset);
            addresses[i * 2] = params.initAddresses[i * 2];
            addresses[i * 2 + 1] = params.initAddresses[i * 2 + 1];
        }
    }

    function getRevenue() external view returns (address[] memory assets_, uint[] memory amounts) {}

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        return _generateDescription($.collateralAsset, $.borrowAsset);
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external pure override returns (string memory, bool) {
        return ("", false);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        assets_ = assets();
        amounts_ = new uint[](1);
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        IERC4626 lendingVault = IERC4626($.lendingVault);
        uint lendShares = lendingVault.balanceOf(address(this));
        amounts_[0] = lendingVault.convertToAssets(lendShares);
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
        __assets = assets();
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {}

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        pure
        override(StrategyBase)
        returns (uint[] memory amountsConsumed, uint value)
    {
        amountsConsumed = new uint[](1);
        amountsConsumed[0] = amountsMax[0];
        value = amountsConsumed[0];
    }

    /// @inheritdoc StrategyBase
    function _depositAssets(uint[] memory amounts, bool /*claimRevenue*/ ) internal override returns (uint value) {
        // get max ltv
        // calc collateral amount
        // calc borrow amount
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {}

    /// @inheritdoc StrategyBase
    function _processRevenue(
        address[] memory, /*assets_*/
        uint[] memory /*amountsRemaining*/
    ) internal pure override returns (bool needCompound) {
        needCompound = true;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _generateDescription(address collateralAsset, address borrowAsset) internal view returns (string memory) {
        return string.concat(
            "Supply ",
            IERC20Metadata(collateralAsset).symbol(),
            " and borrow ",
            IERC20Metadata(borrowAsset).symbol(),
            " on Silo V2 with leverage looping"
        );
    }
}
