// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPool} from "../../integrations/aave/IPool.sol";
import {IAToken} from "../../integrations/aave/IAToken.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../../interfaces/IFactory.sol";
import {ILeverageLendingStrategy} from "../../interfaces/ILeverageLendingStrategy.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IPriceReader} from "../../interfaces/IPriceReader.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SharedLib} from "./SharedLib.sol";
import {StrategyIdLib} from "./StrategyIdLib.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {StrategyLib} from "./StrategyLib.sol";

/// @notice Several standalone functions were moved here to reduce size of ALMFLib
library ALMFLib2 {
    using SafeERC20 for IERC20;

    string internal constant STRATEGY_LOGIC_ID = StrategyIdLib.AAVE_LEVERAGE_MERKL_FARM;

    //region ------------------------------------- View
    function _poolTvl(address platform_, address aToken) external view returns (uint tvlUsd) {
        address asset = IAToken(aToken).UNDERLYING_ASSET_ADDRESS();

        IPriceReader priceReader = IPriceReader(IPlatform(platform_).priceReader());

        // get price of 1 amount of asset in USD with decimals 18
        // assume that {trusted} value doesn't matter here
        // slither-disable-next-line unused-return
        (uint price,) = priceReader.getPrice(asset);

        return IAToken(aToken).totalSupply() * price / (10 ** IERC20Metadata(asset).decimals());
    }

    /// @return targetMinLtv Minimum target ltv, INTERNAL_PRECISION
    /// @return targetMaxLtv Maximum target ltv, INTERNAL_PRECISION
    function _getFarmLtvConfig(IFactory.Farm memory farm) internal pure returns (uint targetMinLtv, uint targetMaxLtv) {
        return (farm.nums[0], farm.nums[1]);
    }

    //endregion ------------------------------------- View

    //region ------------------------------------- Init vars, desc
    function genDesc(IFactory.Farm memory farm) external view returns (string memory) {
        return _genDesc(farm);
    }

    function _genDesc(IFactory.Farm memory farm) internal view returns (string memory) {
        address aToken = farm.addresses[0];
        //slither-disable-next-line calls-loop
        return string.concat(
            "Supply ",
            IERC20Metadata(IAToken(aToken).UNDERLYING_ASSET_ADDRESS()).symbol(),
            " to AAVE ",
            SharedLib.shortAddress(IAToken(aToken).POOL()),
            " with leverage, Merkl rewards"
        );
    }

    /// @dev See IStrategy.initVariants
    function initVariants(address platform_)
        external
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        return SharedLib.initVariantsForFarm(platform_, STRATEGY_LOGIC_ID, _genDesc);
    }

    function getSpecificName(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IFactory.Farm memory farm
    ) external view returns (string memory, bool) {
        (uint targetMinLtv, uint targetMaxLtv) = _getFarmLtvConfig(farm);

        return (
            string.concat(
                IERC20Metadata($.borrowAsset).symbol(),
                " ",
                Strings.toString(targetMinLtv / 100),
                "-",
                Strings.toString(targetMaxLtv / 100)
            ),
            true
        );
    }

    /// @dev A part of initialization code moved here to reduce size of the strategy
    function _postInit(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address platform_,
        address lendingVault_,
        address collateralAsset_,
        address borrowAsset_,
        IFactory.Farm memory farm
    ) external {
        address pool = IAToken(lendingVault_).POOL();
        IERC20(collateralAsset_).forceApprove(pool, type(uint).max);
        IERC20(borrowAsset_).forceApprove(pool, type(uint).max);

        address swapper = IPlatform(platform_).swapper();
        IERC20(collateralAsset_).forceApprove(swapper, type(uint).max);
        IERC20(borrowAsset_).forceApprove(swapper, type(uint).max);

        // ------------------------------ Enable E-Mode for the user account in AAVE if necessary
        uint8 eModeCategoryId = uint8(farm.nums[3]);
        if (eModeCategoryId != 0) {
            // E-mode is activated once here
            // Assume here that collateral and borrow assets are always the same in belong to the given E-category
            // E-mode is never reset because the strategy doesn't use any other borrow assets
            IPool(pool).setUserEMode(eModeCategoryId);
        }

        // ------------------------------ Set up all params in use
        //        // Multiplier of flash amount for borrow on deposit. Default is 100_00 = 100%
        //        $.depositParam0 = 100_00;

        // Deposit fee, percent, 1e4; i.e. 0001 = 0.01%
        // $.depositParam1 = 0;

        // Multiplier of debt diff
        $.increaseLtvParam0 = 100_80;
        // Multiplier of swap borrow asset to collateral in flash loan callback
        $.increaseLtvParam1 = 99_00;
        // Multiplier of collateral diff
        $.decreaseLtvParam0 = 101_00;
        //
        // Swap price impact tolerance, ConstantsLib.DENOMINATOR
        $.swapPriceImpactTolerance0 = 1_000;
        $.swapPriceImpactTolerance1 = 1_000;

        // Leverage correction coefficient, INTERNAL_PRECISION. Default is 300 = 0.03
        $.withdrawParam0 = 300;

        // Withdraw fee, percent, 1e4; i.e. 0001 = 0.01%
        // $.withdrawParam1 = 0;

        //        // withdrawParam2 allows to disable withdraw through increasing ltv if leverage is near to target
        //        $.withdrawParam2 = 100_00;

        $.flashLoanKind = farm.nums[2];
    }

    //endregion ------------------------------------- Init vars, desc

    function liquidateRewards(
        address platform_,
        address exchangeAsset,
        address[] memory rewardAssets_,
        uint[] memory rewardAmounts_,
        uint priceImpactTolerance
    ) external returns (uint earnedExchangeAsset) {
        earnedExchangeAsset = StrategyLib.liquidateRewards(
            platform_, exchangeAsset, rewardAssets_, rewardAmounts_, priceImpactTolerance
        );
    }
}
