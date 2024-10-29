// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../core/libs/CommonLib.sol";
import "../../core/libs/VaultTypeLib.sol";
import "../../core/libs/ConstantsLib.sol";
import "../../interfaces/ILPStrategy.sol";
import "../../interfaces/IPlatform.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/ISwapper.sol";
import "../../interfaces/IRVault.sol";

library LPStrategyLib {
    using SafeERC20 for IERC20;

    uint internal constant SWAP_ASSETS_PRICE_IMPACT_TOLERANCE = 4_000;

    struct ProcessRevenueVars {
        string vaultYpe;
        uint compoundRatio;
        address bbToken;
        uint bbAmountBefore;
    }

    struct SwapForDepositProportionVars {
        ISwapper swapper;
        uint price;
        uint balance0;
        uint balance1;
        uint asset1decimals;
        uint threshold0;
        uint threshold1;
    }

    function LPStrategyBase_init(
        ILPStrategy.LPStrategyBaseStorage storage $,
        address platform,
        ILPStrategy.LPStrategyBaseInitParams memory params,
        string memory ammAdapterId
    ) external returns (address[] memory _assets, uint exchangeAssetIndex) {
        IPlatform.AmmAdapter memory ammAdapterData = IPlatform(platform).ammAdapter(keccak256(bytes(ammAdapterId)));
        if (ammAdapterData.proxy == address(0)) {
            revert ILPStrategy.ZeroAmmAdapter();
        }

        IAmmAdapter ammAdapter = IAmmAdapter(ammAdapterData.proxy);
        _assets = ammAdapter.poolTokens(params.pool);
        uint len = _assets.length;
        exchangeAssetIndex = IFactory(IPlatform(platform).factory()).getExchangeAssetIndex(_assets);
        address swapper = IPlatform(params.platform).swapper();
        // nosemgrep
        for (uint i; i < len; ++i) {
            IERC20(_assets[i]).forceApprove(swapper, type(uint).max);
        }

        $._feesOnBalance = new uint[](_assets.length);
        $.pool = params.pool;
        $.ammAdapter = ammAdapter;
    }

    function checkPreviewDepositAssets(
        address[] memory assets_,
        address[] memory _assets,
        uint[] memory amountsMax
    ) external pure {
        if (_assets.length != amountsMax.length) {
            revert ILPStrategy.IncorrectAmountsLength();
        }
        checkAssets(assets_, _assets);
    }

    function checkAssets(address[] memory assets_, address[] memory _assets) public pure {
        uint len = assets_.length;
        if (len != _assets.length) {
            revert ILPStrategy.IncorrectAssetsLength();
        }
        // nosemgrep
        for (uint i; i < len; ++i) {
            if (assets_[i] != _assets[i]) {
                revert ILPStrategy.IncorrectAssets();
            }
        }
    }

    /// @dev For now this support only pools of 2 tokens
    function processRevenue(
        address platform,
        address vault,
        IAmmAdapter ammAdapter,
        uint exchangeAssetIndex,
        address pool,
        address[] memory assets_,
        uint[] memory amountsRemaining
    ) external returns (bool needCompound) {
        needCompound = true;
        ProcessRevenueVars memory vars;
        vars.vaultYpe = IVault(vault).vaultType();
        if (
            CommonLib.eq(vars.vaultYpe, VaultTypeLib.REWARDING)
                || CommonLib.eq(vars.vaultYpe, VaultTypeLib.REWARDING_MANAGED)
        ) {
            IRVault rVault = IRVault(vault);
            vars.compoundRatio = rVault.compoundRatio();
            vars.bbToken = rVault.bbToken();
            vars.bbAmountBefore = _balance(vars.bbToken);

            {
                uint otherAssetIndex = exchangeAssetIndex == 0 ? 1 : 0;

                uint exchangeAssetBBAmount = (ConstantsLib.DENOMINATOR - vars.compoundRatio)
                    * amountsRemaining[exchangeAssetIndex] / ConstantsLib.DENOMINATOR;
                uint otherAssetBBAmount = (ConstantsLib.DENOMINATOR - vars.compoundRatio)
                    * amountsRemaining[otherAssetIndex] / ConstantsLib.DENOMINATOR;

                // try to make less swaps
                if (otherAssetBBAmount > 0) {
                    if (exchangeAssetBBAmount > 0) {
                        uint otherAssetBBAmountPrice =
                            ammAdapter.getPrice(pool, assets_[otherAssetIndex], address(0), otherAssetBBAmount);
                        uint exchangeAssetAmountRemaining = amountsRemaining[exchangeAssetIndex] - exchangeAssetBBAmount;
                        if (otherAssetBBAmountPrice <= exchangeAssetAmountRemaining) {
                            otherAssetBBAmount = 0;
                            exchangeAssetBBAmount += otherAssetBBAmountPrice;
                        }
                    }
                }

                ISwapper swapper = ISwapper(IPlatform(platform).swapper());

                if (exchangeAssetBBAmount > 0) {
                    if (assets_[exchangeAssetIndex] != vars.bbToken) {
                        if (exchangeAssetBBAmount > swapper.threshold(assets_[exchangeAssetIndex])) {
                            swapper.swap(
                                assets_[exchangeAssetIndex],
                                vars.bbToken,
                                exchangeAssetBBAmount,
                                SWAP_ASSETS_PRICE_IMPACT_TOLERANCE
                            );
                        }
                    } else {
                        vars.bbAmountBefore -= exchangeAssetBBAmount;
                    }
                }
                if (otherAssetBBAmount > 0) {
                    if (assets_[otherAssetIndex] != vars.bbToken) {
                        if (otherAssetBBAmount > swapper.threshold(assets_[otherAssetIndex])) {
                            swapper.swap(
                                assets_[otherAssetIndex],
                                vars.bbToken,
                                otherAssetBBAmount,
                                SWAP_ASSETS_PRICE_IMPACT_TOLERANCE
                            );
                        }
                    } else {
                        vars.bbAmountBefore -= otherAssetBBAmount;
                    }
                }
            }

            uint bbAmount = _balance(vars.bbToken) - vars.bbAmountBefore;

            if (bbAmount > 0) {
                _approveIfNeeded(vars.bbToken, bbAmount, vault);
                rVault.notifyTargetRewardAmount(0, bbAmount);
            }

            if (vars.compoundRatio == 0) {
                needCompound = false;
            }
        }
    }

    /// @dev For now this support only pools of 2 tokens
    function swapForDepositProportion(
        address platform,
        IAmmAdapter ammAdapter,
        address _pool,
        address[] memory assets,
        uint prop0Pool
    ) external returns (uint[] memory amountsToDeposit) {
        amountsToDeposit = new uint[](2);
        SwapForDepositProportionVars memory vars;
        vars.swapper = ISwapper(IPlatform(platform).swapper());
        vars.price = ammAdapter.getPrice(_pool, assets[1], address(0), 0);
        vars.balance0 = _balance(assets[0]);
        vars.balance1 = _balance(assets[1]);
        vars.asset1decimals = IERC20Metadata(assets[1]).decimals();
        vars.threshold0 = vars.swapper.threshold(assets[0]);
        vars.threshold1 = vars.swapper.threshold(assets[1]);
        if (vars.balance0 > vars.threshold0 || vars.balance1 > vars.threshold1) {
            uint balance1PricedInAsset0 = vars.balance1 * vars.price / 10 ** vars.asset1decimals;

            // here is change LPStrategyBase 1.0.3
            // removed such code: `if (!(vars.balance1 > 0 && balance1PricedInAsset0 == 0)) {`
            // because in setup where one of asset if reward asset this condition not work

            uint prop0Balances =
                vars.balance1 > 0 ? vars.balance0 * 1e18 / (balance1PricedInAsset0 + vars.balance0) : 1e18;
            if (prop0Balances > prop0Pool) {
                // extra assets[0]

                uint correctAsset0Balance = (vars.balance0 + balance1PricedInAsset0) * prop0Pool / 1e18;
                uint toSwapAsset0 = vars.balance0 - correctAsset0Balance;

                // this is correct too, but difficult to understand..
                // uint correctAsset0Balance = vars.balance1 * 1e18 / (1e18 - prop0Pool) * prop0Pool / 1e18
                // * vars.price / 10 ** vars.asset1decimals;
                // uint extraBalance = vars.balance0 - correctAsset0Balance;
                // uint toSwapAsset0 = extraBalance - extraBalance * prop0Pool / 1e18;

                // swap assets[0] to assets[1]
                if (toSwapAsset0 > vars.threshold0) {
                    vars.swapper.swap(assets[0], assets[1], toSwapAsset0, SWAP_ASSETS_PRICE_IMPACT_TOLERANCE);
                }
            } else if (prop0Pool > 0) {
                // extra assets[1]
                uint correctAsset1Balance = vars.balance0 * 1e18 / prop0Pool * (1e18 - prop0Pool) / 1e18
                    * 10 ** vars.asset1decimals / vars.price;
                uint extraBalance = vars.balance1 - correctAsset1Balance;
                uint toSwapAsset1 = extraBalance * prop0Pool / 1e18;
                // swap assets[1] to assets[0]
                if (toSwapAsset1 > vars.threshold1) {
                    vars.swapper.swap(assets[1], assets[0], toSwapAsset1, SWAP_ASSETS_PRICE_IMPACT_TOLERANCE);
                }
            }

            amountsToDeposit[0] = _balance(assets[0]);
            amountsToDeposit[1] = _balance(assets[1]);
        }
    }

    function _balance(address token) internal view returns (uint) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Make infinite approve of {token} to {spender} if the approved amount is less than {amount}
    /// @dev Should NOT be used for third-party pools
    function _approveIfNeeded(address token, uint amount, address spender) internal {
        if (IERC20(token).allowance(address(this), spender) < amount) {
            // infinite approve, 2*255 is more gas efficient then type(uint).max
            IERC20(token).forceApprove(spender, 2 ** 255);
        }
    }
}
