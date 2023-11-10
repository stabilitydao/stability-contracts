// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../core/libs/ConstantsLib.sol";
import "../../core/libs/VaultTypeLib.sol";
import "../../core/libs/CommonLib.sol";
import "../../interfaces/IPlatform.sol";
import "../../interfaces/IVault.sol";
import "../../interfaces/IVaultManager.sol";
import "../../interfaces/IStrategyLogic.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IPriceReader.sol";
import "../../interfaces/ISwapper.sol";
import "../../interfaces/IPairStrategyBase.sol";
import "../../interfaces/IRVault.sol";

library StrategyLib {
    using SafeERC20 for IERC20;

    event HardWork(uint apr, uint compoundApr, uint earned, uint tvl, uint duration, uint sharePrice);
    event ExtractFees(uint vaultManagerReceiverFee, uint strategyLogicReceiverFee, uint ecosystemRevenueReceiverFee, uint multisigReceiverFee);

    struct PairStrategyBaseSwapForDepositProportionVars {
        ISwapper swapper;
        uint price;
        uint balance0;
        uint balance1;
        uint asset1decimals;
        uint threshold0;
        uint threshold1;
    }

    struct ProcessRevenueVars {
        string vaultYpe;
        uint compoundRatio;
        address bbToken;
        uint bbAmountBefore;
    }

    struct ExtractFeesVars {
        IPlatform platform;
        uint feePlatform;
        uint amountPlatform;
        uint feeShareVaultManager;
        uint amountVaultManager;
        uint feeShareStrategyLogic;
        uint amountStrategyLogic;
        uint feeShareEcosystem;
        uint amountEcosystem;
    }

    function PairStrategyBase_init(
        address platform,
        IPairStrategyBase.PairStrategyBaseInitParams memory params,
        string memory dexAdapterId
    ) external returns(address[] memory _assets, uint exchangeAssetIndex, IDexAdapter dexAdapter) {
        IPlatform.DexAdapter memory dexAdapterData = IPlatform(platform).dexAdapter(keccak256(bytes(dexAdapterId)));
        require(dexAdapterData.proxy != address(0), "StrategyLib: zero DeX adapter");
        dexAdapter = IDexAdapter(dexAdapterData.proxy);
        _assets = dexAdapter.poolTokens(params.pool);
        uint len = _assets.length;
        exchangeAssetIndex = IFactory(IPlatform(platform).factory()).getExchangeAssetIndex(_assets);
        address swapper = IPlatform(params.platform).swapper();
        for (uint i; i < len; ++i) {
            IERC20(_assets[i]).forceApprove(swapper, type(uint).max);
        }
    }

    function FarmingStrategyBase_init(string memory id, address platform, uint farmId) external returns (address[] memory rewardAssets) {
        IFactory.Farm memory farm = IFactory(IPlatform(platform).factory()).farm(farmId);
        require (keccak256(bytes(farm.strategyLogicId)) == keccak256(bytes(id)), "FarmingStrategyBase: incorrect strategy id");
        uint len = farm.rewardAssets.length;
        address swapper = IPlatform(platform).swapper();
        for (uint i; i < len; ++i) {
            IERC20(farm.rewardAssets[i]).forceApprove(swapper, type(uint).max);
        }
        rewardAssets = farm.rewardAssets;
    }

    function transferAssets(
        address[] memory assets,
        uint amount,
        uint total_,
        address receiver
    ) external returns (uint[] memory amountsOut) {
        uint len = assets.length;
        amountsOut = new uint[](len);
        for (uint i; i < len; ++i) {
            amountsOut[i] = IERC20(assets[i]).balanceOf(address(this)) * amount / total_;
            amountsOut[i] = IERC20(assets[i]).balanceOf(address(this)) * amount / total_;
            IERC20(assets[i]).transfer(receiver, amountsOut[i]);
        }
    }

    function extractFees(
        address platform,
        address vault,
        string memory _id,
        address[] memory assets_,
        uint[] memory amounts_
    ) external returns(uint[] memory amountsRemaining) {
        ExtractFeesVars memory vars = ExtractFeesVars({
            platform: IPlatform(platform),
            feePlatform: 0,
            amountPlatform: 0,
            feeShareVaultManager: 0,
            amountVaultManager: 0,
            feeShareStrategyLogic: 0,
            amountStrategyLogic: 0,
            feeShareEcosystem: 0,
            amountEcosystem: 0
        });
        // IPlatform _platform = IPlatform(platform);
        // uint[] memory fees = new uint[](4);
        // uint[] memory feeAmounts = new uint[](4);
        (vars.feePlatform, vars.feeShareVaultManager, vars.feeShareStrategyLogic, vars.feeShareEcosystem) = vars.platform.getFees();
        address vaultManagerReceiver = IVaultManager(vars.platform.vaultManager()).getRevenueReceiver(IVault(vault).tokenId());
        //slither-disable-next-line unused-return
        (,,,,,uint strategyLogicTokenId) = IFactory(vars.platform.factory()).strategyLogicConfig(keccak256(bytes(_id)));
        address strategyLogicReceiver = IStrategyLogic(vars.platform.strategyLogic()).getRevenueReceiver(strategyLogicTokenId);
        uint len = assets_.length;
        amountsRemaining = new uint[](len);
        for (uint i; i < len; ++i) {
            if (amounts_[i] > 0) {
                // revenue fee amount of assets_[i]
                vars.amountPlatform = amounts_[i] * vars.feePlatform / ConstantsLib.DENOMINATOR;

                amountsRemaining[i] = amounts_[i] - vars.amountPlatform;

                // VaultManager amount
                vars.amountVaultManager = vars.amountPlatform * vars.feeShareVaultManager / ConstantsLib.DENOMINATOR;

                // StrategyLogic amount
                vars.amountStrategyLogic = vars.amountPlatform * vars.feeShareStrategyLogic / ConstantsLib.DENOMINATOR;

                // Ecosystem amount
                vars.amountEcosystem = vars.amountPlatform  * vars.feeShareEcosystem / ConstantsLib.DENOMINATOR;

                // Multisig share and amount
                uint multisigShare = ConstantsLib.DENOMINATOR - vars.feeShareVaultManager - vars.feeShareStrategyLogic - vars.feeShareEcosystem;
                uint multisigAmount = multisigShare > 0 ? vars.amountPlatform  - vars.amountVaultManager - vars.amountStrategyLogic - vars.amountEcosystem : 0;

                // send amounts
                IERC20(assets_[i]).safeTransfer(vaultManagerReceiver, vars.amountVaultManager);
                IERC20(assets_[i]).safeTransfer(strategyLogicReceiver, vars.amountStrategyLogic);
                if (vars.amountEcosystem > 0) {
                    IERC20(assets_[i]).safeTransfer(vars.platform.ecosystemRevenueReceiver(), vars.amountEcosystem);
                }
                if (multisigAmount > 0) {
                    IERC20(assets_[i]).safeTransfer(vars.platform.multisig(), multisigAmount);
                }
                emit ExtractFees(vars.amountVaultManager, vars.amountStrategyLogic, vars.amountEcosystem, multisigAmount);
            }
        }
    }

    function liquidateRewards(address platform, address exchangeAsset, address[] memory rewardAssets_, uint[] memory rewardAmounts_) external returns (uint earnedExchangeAsset) {
        ISwapper swapper = ISwapper(IPlatform(platform).swapper());
        uint len = rewardAssets_.length;
        uint exchangeAssetBalanceBefore = balance(exchangeAsset);
        for (uint i; i < len; ++i) {
            if (rewardAmounts_[i] > swapper.threshold(rewardAssets_[i])) {
                swapper.swap(rewardAssets_[i], exchangeAsset, rewardAmounts_[i], ConstantsLib.SWAP_REVENUE_PRICE_IMPACT_TOLERANCE);
            }
        }
        uint exchangeAssetBalanceAfter = balance(exchangeAsset);
        earnedExchangeAsset = exchangeAssetBalanceAfter - exchangeAssetBalanceBefore;
    }

    function emitApr(
        uint lastHardWork,
        address platform,
        address[] memory assets,
        uint[] memory amounts,
        uint tvl,
        uint totalBefore,
        uint totalAfter,
        address vault
    ) external returns(uint apr, uint aprCompound) {
        uint duration = block.timestamp - lastHardWork;
        IPriceReader priceReader = IPriceReader(IPlatform(platform).priceReader());
        //slither-disable-next-line unused-return
        (uint earned,,) = priceReader.getAssetsPrice(assets, amounts);
        apr = computeApr(tvl, earned, duration);
        aprCompound = computeApr(totalBefore, totalAfter - totalBefore, duration);
        uint sharePrice = tvl * 1e18 / IERC20(vault).totalSupply();
        emit HardWork(apr, aprCompound, earned, tvl, duration, sharePrice);
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

    /// @notice Make infinite approve of {token} to {spender} if the approved amount is less than {amount}
    /// @dev Should NOT be used for third-party pools
    function approveIfNeeded(address token, uint amount, address spender) public {
        if (IERC20(token).allowance(address(this), spender) < amount) {
            // infinite approve, 2*255 is more gas efficient then type(uint).max
            IERC20(token).forceApprove(spender, 2 ** 255);
        }
    }

    function processRevenue(
        address platform,
        address vault,
        IDexAdapter dexAdapter,
        uint exchangeAssetIndex,
        address pool,
        address[] memory assets_,
        uint[] memory amountsRemaining
    ) external returns (bool needCompound) {
        needCompound = true;
        ProcessRevenueVars memory vars;
        vars.vaultYpe = IVault(vault).VAULT_TYPE();
        if (
            CommonLib.eq(vars.vaultYpe, VaultTypeLib.REWARDING)
            || CommonLib.eq(vars.vaultYpe, VaultTypeLib.REWARDING_MANAGED)
        ) {
            IRVault rVault = IRVault(vault);
            vars.compoundRatio = rVault.compoundRatio();
            vars.bbToken = rVault.bbToken();
            vars.bbAmountBefore = balance(vars.bbToken);

            {
                uint otherAssetIndex = exchangeAssetIndex == 0 ? 1 : 0;

                uint exchangeAssetBBAmount = (ConstantsLib.DENOMINATOR - vars.compoundRatio) * amountsRemaining[exchangeAssetIndex] / ConstantsLib.DENOMINATOR;
                uint otherAssetBBAmount = (ConstantsLib.DENOMINATOR - vars.compoundRatio) * amountsRemaining[otherAssetIndex] / ConstantsLib.DENOMINATOR;

                // try to make less swaps
                if (otherAssetBBAmount > 0 && exchangeAssetBBAmount > 0) {
                    uint otherAssetBBAmountPrice = dexAdapter.getPrice(pool, assets_[otherAssetIndex], address(0), otherAssetBBAmount);
                    uint exchangeAssetAmountRemaining = amountsRemaining[exchangeAssetIndex] - exchangeAssetBBAmount;
                    if (otherAssetBBAmountPrice <= exchangeAssetAmountRemaining) {
                        otherAssetBBAmount = 0;
                        exchangeAssetBBAmount += otherAssetBBAmountPrice;
                    }
                }

                ISwapper swapper = ISwapper(IPlatform(platform).swapper());

                if (exchangeAssetBBAmount > 0) {
                    if (assets_[exchangeAssetIndex] != vars.bbToken) {
                        if (exchangeAssetBBAmount > swapper.threshold(assets_[exchangeAssetIndex])) {
                            swapper.swap(assets_[exchangeAssetIndex], vars.bbToken, exchangeAssetBBAmount, ConstantsLib.SWAP_REVENUE_PRICE_IMPACT_TOLERANCE);
                        }
                    } else {
                        vars.bbAmountBefore -= exchangeAssetBBAmount;
                    }
                }
                if (otherAssetBBAmount > 0) {
                    if (assets_[otherAssetIndex] != vars.bbToken) {
                        if (otherAssetBBAmount > swapper.threshold(assets_[otherAssetIndex])) {
                            swapper.swap(assets_[otherAssetIndex], vars.bbToken, otherAssetBBAmount, ConstantsLib.SWAP_REVENUE_PRICE_IMPACT_TOLERANCE);
                        }
                    } else {
                        vars.bbAmountBefore -= otherAssetBBAmount;
                    }
                }
            }

            uint bbAmount = balance(vars.bbToken) - vars.bbAmountBefore;

            if (bbAmount > 0) {
                approveIfNeeded(vars.bbToken, bbAmount, vault);
                rVault.notifyTargetRewardAmount(0, bbAmount);
            }

            if (vars.compoundRatio == 0) {
                needCompound = false;
            }
        }
    }

    function checkPairStrategyBasePreviewDepositAssets(address[] memory assets_, address[] memory _assets, uint[] memory amountsMax) external pure {
        require(amountsMax.length == 2, "PairStrategyBase: incorrect length");
        require(assets_.length == 2, "PairStrategyBase: incorrect length");
        require(assets_[0] == _assets[0] && assets_[1] == _assets[1], "PairStrategyBase: incorrect assets");
    }

    function checkPairStrategyBaseWithdrawAssets(address[] memory assets_, address[] memory _assets) external pure {
        require(assets_.length == 2, "PairStrategyBase: incorrect length");
        require(assets_[0] == _assets[0] && assets_[1] == _assets[1], "PairStrategyBase: incorrect assets");
    }

    function revertUnderlying(address underlying) external pure {
        revert(underlying == address(0) ? 'StrategyBase: no underlying' : 'StrategyBase: not implemented');
    }

    function pairStrategyBaseSwapForDepositProportion(
        address platform,
        IDexAdapter dexAdapter,
        address _pool,
        address[] memory assets,
        uint prop0Pool
    ) external returns(uint[] memory amountsToDeposit) {
        amountsToDeposit = new uint[](2);
        PairStrategyBaseSwapForDepositProportionVars memory vars;
        vars.swapper = ISwapper(IPlatform(platform).swapper());
        vars.price = dexAdapter.getPrice(_pool, assets[1], address(0), 0);
        vars.balance0 = balance(assets[0]);
        vars.balance1 = balance(assets[1]);
        vars.asset1decimals = IERC20Metadata(assets[1]).decimals();
        vars.threshold0 = vars.swapper.threshold(assets[0]);
        vars.threshold1 = vars.swapper.threshold(assets[1]);
        if (vars.balance0 > vars.threshold0 || vars.balance1 > vars.threshold1) {
            uint balance1PricedInAsset0 = vars.balance1 * vars.price / 10 ** vars.asset1decimals;

            if (!(vars.balance1 > 0 && balance1PricedInAsset0 == 0)) {
                uint prop0Balances = vars.balance1 > 0 ? vars.balance0 * 1e18 / (balance1PricedInAsset0 + vars.balance0) : 1e18;
                if (prop0Balances > prop0Pool) {
                    // extra assets[0]
                    uint correctAsset0Balance = vars.balance1 * 1e18 / (1e18 - prop0Pool) * prop0Pool / 1e18 * vars.price / 10 ** vars.asset1decimals;
                    uint extraBalance = vars.balance0 - correctAsset0Balance;
                    uint toSwapAsset0 = extraBalance - extraBalance * prop0Pool / 1e18;
                    // swap assets[0] to assets[1]
                    if (toSwapAsset0 > vars.threshold0) {
                        vars.swapper.swap(assets[0], assets[1], toSwapAsset0, ConstantsLib.SWAP_REVENUE_PRICE_IMPACT_TOLERANCE);
                    }
                } else {
                    // extra assets[1]
                    uint correctAsset1Balance = vars.balance0 * 1e18 / prop0Pool * (1e18 - prop0Pool) / 1e18 * 10 ** vars.asset1decimals / vars.price;
                    uint extraBalance = vars.balance1 - correctAsset1Balance;
                    uint toSwapAsset1 = extraBalance * prop0Pool / 1e18;
                    // swap assets[1] to assets[0]
                    if (toSwapAsset1 > vars.threshold1) {
                        vars.swapper.swap(assets[1], assets[0], toSwapAsset1, ConstantsLib.SWAP_REVENUE_PRICE_IMPACT_TOLERANCE);
                    }
                }

                amountsToDeposit[0] = balance(assets[0]);
                amountsToDeposit[1] = balance(assets[1]);
            }
        }
    }

    function assetsAmountsWithBalances(address[] memory assets_, uint[] memory amounts_) external view returns (address[] memory assets, uint[] memory amounts) {
        assets = assets_;
        amounts = amounts_;
        uint len = assets_.length;
        for (uint i; i < len; ++i) {
            amounts[i] += balance(assets_[i]);
        }
    }

    function getFarmsForStrategyId(address platform, string memory _id) external view returns (IFactory.Farm[] memory farms) {
        uint total;
        IFactory.Farm[] memory allFarms = IFactory(IPlatform(platform).factory()).farms();
        uint len = allFarms.length;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = allFarms[i];
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, _id)) {
                total++;
            }
        }
        farms = new IFactory.Farm[](total);
        uint k;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = allFarms[i];
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, _id)) {
                farms[k] = farm;
                k++;
            }
        }
    }

}
