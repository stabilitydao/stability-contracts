// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ConstantsLib} from "../../core/libs/ConstantsLib.sol";
import {CommonLib} from "../../core/libs/CommonLib.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IVaultManager} from "../../interfaces/IVaultManager.sol";
import {IFactory} from "../../interfaces/IFactory.sol";
import {IPriceReader} from "../../interfaces/IPriceReader.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {IFarmingStrategy} from "../../interfaces/IFarmingStrategy.sol";
import {IRevenueRouter} from "../../interfaces/IRevenueRouter.sol";

library StrategyLib {
    using SafeERC20 for IERC20;

    /// @dev Reward pools may have low liquidity and up to 2% fees
    uint internal constant SWAP_REWARDS_PRICE_IMPACT_TOLERANCE = 7_000;

    struct ExtractFeesVars {
        IPlatform platform;
        uint feePlatform;
        uint amountPlatform;
    }

    function FarmingStrategyBase_init(
        IFarmingStrategy.FarmingStrategyBaseStorage storage $,
        string memory id,
        address platform,
        uint farmId
    ) external {
        $.farmId = farmId;

        IFactory.Farm memory farm = IFactory(IPlatform(platform).factory()).farm(farmId);
        if (keccak256(bytes(farm.strategyLogicId)) != keccak256(bytes(id))) {
            revert IFarmingStrategy.IncorrectStrategyId();
        }

        updateFarmingAssets($, platform);

        $._rewardsOnBalance = new uint[](farm.rewardAssets.length);
    }

    function updateFarmingAssets(IFarmingStrategy.FarmingStrategyBaseStorage storage $, address platform) public {
        IFactory.Farm memory farm = IFactory(IPlatform(platform).factory()).farm($.farmId);
        address swapper = IPlatform(platform).swapper();
        $._rewardAssets = farm.rewardAssets;
        uint len = farm.rewardAssets.length;
        // nosemgrep
        for (uint i; i < len; ++i) {
            IERC20(farm.rewardAssets[i]).forceApprove(swapper, type(uint).max);
        }
        $._rewardsOnBalance = new uint[](len);
    }

    function transferAssets(
        IStrategy.StrategyBaseStorage storage $,
        uint amount,
        uint total_,
        address receiver
    ) external returns (uint[] memory amountsOut) {
        address[] memory assets = $._assets;

        uint len = assets.length;
        amountsOut = new uint[](len);
        // nosemgrep
        for (uint i; i < len; ++i) {
            amountsOut[i] = balance(assets[i]) * amount / total_;
            IERC20(assets[i]).transfer(receiver, amountsOut[i]);
        }
    }

    function extractFees(
        address platform,
        address vault,
        address[] memory assets_,
        uint[] memory amounts_
    ) external returns (uint[] memory amountsRemaining) {
        ExtractFeesVars memory vars =
            ExtractFeesVars({platform: IPlatform(platform), feePlatform: 0, amountPlatform: 0});

        (vars.feePlatform,,,) = vars.platform.getFees();
        try vars.platform.getCustomVaultFee(vault) returns (uint vaultCustomFee) {
            if (vaultCustomFee != 0) {
                vars.feePlatform = vaultCustomFee;
            }
        } catch {}

        uint len = assets_.length;
        amountsRemaining = new uint[](len);
        // nosemgrep
        for (uint i; i < len; ++i) {
            // revenue fee amount of assets_[i]
            vars.amountPlatform = amounts_[i] * vars.feePlatform / ConstantsLib.DENOMINATOR;
            vars.amountPlatform = Math.min(vars.amountPlatform, balance(assets_[i]));

            if (vars.amountPlatform > 0) {
                try vars.platform.revenueRouter() returns (address revenueReceiver) {
                    IERC20(assets_[i]).forceApprove(revenueReceiver, vars.amountPlatform);
                    IRevenueRouter(revenueReceiver).processFeeAsset(assets_[i], vars.amountPlatform);
                } catch {
                    // can be only in old strategy upgrade tests
                }
                amountsRemaining[i] = amounts_[i] - vars.amountPlatform;
                amountsRemaining[i] = Math.min(amountsRemaining[i], balance(assets_[i]));
            }
        }
    }

    function liquidateRewards(
        address platform,
        address exchangeAsset,
        address[] memory rewardAssets_,
        uint[] memory rewardAmounts_,
        uint customPriceImpactTolerance
    ) external returns (uint earnedExchangeAsset) {
        ISwapper swapper = ISwapper(IPlatform(platform).swapper());
        uint len = rewardAssets_.length;
        uint exchangeAssetBalanceBefore = balance(exchangeAsset);
        // nosemgrep
        for (uint i; i < len; ++i) {
            if (rewardAmounts_[i] > swapper.threshold(rewardAssets_[i])) {
                if (rewardAssets_[i] != exchangeAsset) {
                    swapper.swap(
                        rewardAssets_[i],
                        exchangeAsset,
                        Math.min(rewardAmounts_[i], balance(rewardAssets_[i])),
                        customPriceImpactTolerance != 0
                            ? customPriceImpactTolerance
                            : SWAP_REWARDS_PRICE_IMPACT_TOLERANCE
                    );
                } else {
                    exchangeAssetBalanceBefore = 0;
                }
            }
        }
        uint exchangeAssetBalanceAfter = balance(exchangeAsset);
        earnedExchangeAsset = exchangeAssetBalanceAfter - exchangeAssetBalanceBefore;
    }

    function emitApr(
        IStrategy.StrategyBaseStorage storage $,
        address platform,
        address[] memory assets,
        uint[] memory amounts,
        uint tvl,
        uint totalBefore
    ) external {
        uint duration = block.timestamp - $.lastHardWork;
        IPriceReader priceReader = IPriceReader(IPlatform(platform).priceReader());
        //slither-disable-next-line unused-return
        (uint earned,, uint[] memory assetPrices,) = priceReader.getAssetsPrice(assets, amounts);
        uint apr = computeApr(tvl, earned, duration);
        uint aprCompound = totalBefore != 0 ? computeApr(totalBefore, $.total - totalBefore, duration) : apr;

        uint sharePrice = tvl * 1e18 / IERC20($.vault).totalSupply();
        emit IStrategy.HardWork(apr, aprCompound, earned, tvl, duration, sharePrice, assetPrices);
        $.lastApr = apr;
        $.lastAprCompound = aprCompound;
        $.lastHardWork = block.timestamp;
    }

    function balance(address token) public view returns (uint) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @dev https://www.investopedia.com/terms/a/apr.asp
    ///      TVL and rewards should be in the same currency and with the same decimals
    function computeApr(uint tvl, uint earned, uint duration) public pure returns (uint) {
        if (tvl == 0 || duration == 0) {
            return 0;
        }
        return earned * 1e18 * ConstantsLib.DENOMINATOR * uint(365) / tvl / (duration * 1e18 / 1 days);
    }

    function computeAprInt(uint tvl, int earned, uint duration) public pure returns (int) {
        if (tvl == 0 || duration == 0) {
            return 0;
        }
        return earned * int(1e18) * int(ConstantsLib.DENOMINATOR) * int(365) / int(tvl) / int(duration * 1e18 / 1 days);
    }

    function assetsAmountsWithBalances(
        address[] memory assets_,
        uint[] memory amounts_
    ) external view returns (address[] memory assets, uint[] memory amounts) {
        assets = assets_;
        amounts = amounts_;
        uint len = assets_.length;
        // nosemgrep
        for (uint i; i < len; ++i) {
            amounts[i] += balance(assets_[i]);
        }
    }

    function assetsAreOnBalance(address[] memory assets) external view returns (bool isReady) {
        uint rwLen = assets.length;
        for (uint i; i < rwLen; ++i) {
            if (IERC20(assets[i]).balanceOf(address(this)) > 0) {
                isReady = true;
                break;
            }
        }
    }

    function isPositiveAmountInArray(uint[] memory amounts) external pure returns (bool) {
        uint len = amounts.length;
        for (uint i; i < len; ++i) {
            if (amounts[i] != 0) {
                return true;
            }
        }
        return false;
    }

    function swap(address platform, address tokenIn, address tokenOut, uint amount) external returns (uint amountOut) {
        uint outBalanceBefore = balance(tokenOut);
        ISwapper swapper = ISwapper(IPlatform(platform).swapper());
        swapper.swap(tokenIn, tokenOut, amount, 1000);
        amountOut = balance(tokenOut) - outBalanceBefore;
    }

    function swap(
        address platform,
        address tokenIn,
        address tokenOut,
        uint amount,
        uint priceImpactTolerance
    ) external returns (uint amountOut) {
        uint outBalanceBefore = balance(tokenOut);
        ISwapper swapper = ISwapper(IPlatform(platform).swapper());
        swapper.swap(tokenIn, tokenOut, amount, priceImpactTolerance);
        amountOut = balance(tokenOut) - outBalanceBefore;
    }

    // function getFarmsForStrategyId(address platform, string memory _id) external view returns (IFactory.Farm[] memory farms) {
    //     uint total;
    //     IFactory.Farm[] memory allFarms = IFactory(IPlatform(platform).factory()).farms();
    //     uint len = allFarms.length;
    //     for (uint i; i < len; ++i) {
    //         IFactory.Farm memory farm = allFarms[i];
    //         if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, _id)) {
    //             total++;
    //         }
    //     }
    //     farms = new IFactory.Farm[](total);
    //     uint k;
    //     for (uint i; i < len; ++i) {
    //         IFactory.Farm memory farm = allFarms[i];
    //         if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, _id)) {
    //             farms[k] = farm;
    //             k++;
    //         }
    //     }
    // }
}
