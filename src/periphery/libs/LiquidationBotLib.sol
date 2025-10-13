// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IMetaVault} from "../../interfaces/IMetaVault.sol";
import {IWrappedMetaVault} from "../../interfaces/IWrappedMetaVault.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IAaveAddressProvider} from "../../integrations/aave/IAaveAddressProvider.sol";
import {IAaveDataProvider} from "../../integrations/aave/IAaveDataProvider.sol";
import {IAavePriceOracle} from "../../integrations/aave/IAavePriceOracle.sol";
import {IBVault} from "../../integrations/balancer/IBVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILeverageLendingStrategy} from "../../interfaces/ILeverageLendingStrategy.sol";
import {ILiquidationBot} from "../../interfaces/ILiquidationBot.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IPool} from "../../integrations/aave/IPool.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {IUniswapV3PoolActions} from "../../integrations/uniswapv3/pool/IUniswapV3PoolActions.sol";
import {IUniswapV3PoolImmutables} from "../../integrations/uniswapv3/pool/IUniswapV3PoolImmutables.sol";
import {IVaultMainV3} from "../../integrations/balancerv3/IVaultMainV3.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library LiquidationBotLib {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.LiquidationBot")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant _LIQUIDATION_BOT_STORAGE_LOCATION =
        0x362967b05e4803bd3245d8827f04dccb46602717711e075af724a3f0f67edb00;

    uint internal constant DEFAULT_SWAP_PRICE_IMPACT_TOLERANCE = 1_000; // 1% with denominator 100_000

    //region -------------------------------------- Data types

    error UnauthorizedCallback();
    error NotWhitelisted();
    error IncorrectAmountReceived(address asset, uint balanceBefore, uint balanceAfter, uint expectedAmount);
    error InsufficientBalanceToPayFlash(uint availableBalance, uint requiredBalance);
    error InsufficientFlashBalance(uint availableBalance, uint requiredBalance);
    error InvalidHealthFactor();
    error HealthFactorNotIncreased(uint healthFactorBefore, uint healthFactorAfter);
    error NoProfit();

    event Liquidation(
        address user,
        ILiquidationBot.UserAccountData userDataBefore,
        ILiquidationBot.UserAccountData userDataAfter,
        address debtAsset,
        uint debtRepaid,
        address collateralAsset,
        uint profitReceived,
        uint amountToProfitTarget
    );
    event Profit(address fromUser, address asset, uint amount, address targetProfit);
    event UserSkipped(address user, ILiquidationBot.UserAccountData userData, ILiquidationBot.UserPosition position);

    event SetFlashLoan(address vault, uint kind);
    event SetPriceImpactTolerance(uint priceImpactTolerance);
    event SetProfitTarget(address profitTarget);
    event Whitelist(address operator, bool add);
    event SetWrappedMetaVault(address metaVault, bool add);
    /// @param targetHealthFactor Target health factor, decimals 18
    event SetTargetHealthFactory(uint targetHealthFactor);
    event OnLiquidation(address aavePool, address user, uint repayAmount, uint collateralReceived);

    /// @custom:storage-location erc7201:stability.LiquidationBot
    struct LiquidationBotStorage {
        /// @notice Whitelisted operators that can call main actions
        mapping(address operator => bool allowed) whitelistOperators;
        /// @notice All registered wrapped meta-vaults. If collateral asset is a wrapped meta-vault,
        /// the contract should disable last-block-defense during liquidation
        /// to be able to swap received collateral immediately after liquidation and repay flash loan
        mapping(address wrappedMetaVault => uint isWrappedMetaVault) wrappedMetaVaults;
        /// @notice A contract to send profit to
        address profitTarget;
        /// @notice Address of the vault to take flash loans from (if needed).
        /// The type of vault is determined by the {flashLoanKind}
        address flashLoanVault;
        /// @notice Same values as in ILeverageLendingStrategy.FlashLoanKind flashLoanKind
        /// But not possible values can be supported, see the code below
        uint flashLoanKind;
        /// @notice Price impact tolerance. Denominator is 100_000.
        /// @dev if 0 then DEFAULT_SWAP_PRICE_IMPACT_TOLERANCE is used
        uint priceImpactTolerance;
        /// @notice What health factor should be reached after liquidation ( > 1e18 )
        /// 0 - means that max possible debt should be repaid (up to 50% of total debt)
        uint targetHealthFactor;
    }

    struct AaveContracts {
        IPool pool;
        IAaveDataProvider dataProvider;
        IAavePriceOracle oracle;
    }

    struct ReserveData {
        address asset;
        uint ltv;
        uint liquidationThreshold;
        uint decimals;
        uint liquidationBonus;
    }

    struct UserData {
        address aavePool;
        address user;
        address collateralAsset;
        address debtAsset;
        /// @param collateralAmount_ Total amount of the collateral asset the user has
        uint collateralAmount;
        /// @param repayAmount_ Amount of the debt asset to repay
        uint repayAmount;
    }

    //endregion -------------------------------------- Data types

    //region -------------------------------------- Main logic

    /// @notice Make liquidation, send profit to the registered contract
    /// @param users List of users to liquidate (users with health factor < 1)
    /// @param targetHealthFactor_ Use type(uint).max to use default target health factor
    function liquidate(AaveContracts memory ac, address[] memory users, uint targetHealthFactor_) internal {
        LiquidationBotStorage storage $ = getLiquidationBotStorage();

        uint len = users.length;
        for (uint i; i < len; ++i) {
            ILiquidationBot.UserAccountData memory userData0 = getUserAccountData(ac, users[i]);
            ILiquidationBot.UserPosition memory position = _getUserPosition(users[i], ac.dataProvider);

            if (
                userData0.healthFactor >= 1e18 || position.collateralReserve == address(0)
                    || position.debtReserve == address(0)
            ) {
                emit UserSkipped(users[i], userData0, position);
            } else {
                uint repayAmount = _getRepayAmount(
                    ac,
                    position.collateralReserve,
                    position.debtReserve,
                    userData0,
                    targetHealthFactor_ == type(uint).max ? $.targetHealthFactor : targetHealthFactor_
                );
                uint balanceBefore = IERC20(position.debtReserve).balanceOf(address(this));

                _requestFlashLoanExplicit(
                    $.flashLoanKind,
                    $.flashLoanVault,
                    position.debtReserve,
                    repayAmount,
                    abi.encode(_getUserData(address(ac.pool), users[i], position, repayAmount))
                );

                uint balanceAfter = IERC20(position.debtReserve).balanceOf(address(this));
                uint profit = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;

                _sendProfit($, users[i], position.debtReserve, balanceAfter);

                ILiquidationBot.UserAccountData memory userData1 = getUserAccountData(ac, users[i]);

                // require(userData0.healthFactor < userData1.healthFactor, HealthFactorNotIncreased(userData0.healthFactor, userData1.healthFactor));
                require(profit != 0, NoProfit());

                emit Liquidation(
                    users[i],
                    userData0,
                    userData1,
                    position.debtReserve,
                    position.debtAmount,
                    position.collateralReserve,
                    profit,
                    balanceAfter
                );
            }
        }
    }

    //endregion -------------------------------------- Main logic

    //region -------------------------------------- Restricted actions
    /// @notice Set flash loan vault and kind
    function setFlashLoanVault(address flashLoanVault, uint flashLoanKind) internal {
        LiquidationBotStorage storage $ = getLiquidationBotStorage();
        $.flashLoanKind = flashLoanKind;
        $.flashLoanVault = flashLoanVault;

        emit SetFlashLoan(flashLoanVault, flashLoanKind);
    }

    /// @notice Set price impact tolerance. Denominator is 100_000.
    function setPriceImpactTolerance(uint priceImpactTolerance_) internal {
        LiquidationBotStorage storage $ = getLiquidationBotStorage();
        $.priceImpactTolerance = priceImpactTolerance_;

        emit SetPriceImpactTolerance(priceImpactTolerance_);
    }

    /// @notice Set address of the contract where profit will be sent
    function setProfitTarget(address profitTarget) internal {
        LiquidationBotStorage storage $ = getLiquidationBotStorage();
        $.profitTarget = profitTarget;

        emit SetProfitTarget(profitTarget);
    }

    /// @notice Add or remove operator from the whitelist
    function changeWhitelist(address operator_, bool add_) internal {
        LiquidationBotStorage storage $ = getLiquidationBotStorage();
        $.whitelistOperators[operator_] = add_;

        emit Whitelist(operator_, add_);
    }

    /// @notice Add or remove wrapped meta vault to/from the list of registered wrapped meta vaults
    function changeWrappedMetaVault(address wrappedMetaVault_, bool add_) internal {
        LiquidationBotStorage storage $ = getLiquidationBotStorage();
        $.wrappedMetaVaults[wrappedMetaVault_] = add_ ? 1 : 0;

        emit SetWrappedMetaVault(wrappedMetaVault_, add_);
    }

    /// @notice Target health factor for the users after liquidation
    /// @param targetHealthFactor_ Target health factor, decimals 18, must be > 1e18
    /// 0 - means that max possible debt should be repaid (up to 50% of total debt)
    function setTargetHealthFactor(uint targetHealthFactor_) internal {
        LiquidationBotStorage storage $ = getLiquidationBotStorage();
        // require(targetHealthFactor_ == 0, InvalidHealthFactor());

        $.targetHealthFactor = targetHealthFactor_;
        emit SetTargetHealthFactory(targetHealthFactor_);
    }
    //endregion -------------------------------------- Restricted actions

    //region -------------------------------------- Flash loan

    /// @notice Get flash loan
    /// @dev This version of function passes {userData} to the callback
    function _requestFlashLoanExplicit(
        uint flashLoanKind,
        address flashLoanVault,
        address flashAsset_,
        uint flashAmount_,
        bytes memory userData
    ) internal {
        if (flashLoanKind == uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1)) {
            // --------------- Flash loan of Balancer v3, free. The strategy should support IBalancerV3FlashCallback
            // fee amount are always 0, flash loan in balancer v3 is free
            bytes memory data = abi.encodeWithSignature(
                "receiveFlashLoanV3(address,uint256,bytes)", flashAsset_, flashAmount_, userData
            );

            IVaultMainV3(payable(flashLoanVault)).unlock(data);
        } else {
            address[] memory flashAssets = new address[](1);
            flashAssets[0] = flashAsset_;
            uint[] memory flashAmounts = new uint[](1);
            flashAmounts[0] = flashAmount_;

            if (
                // assume here that Algebra uses exactly same API as UniswapV3
                flashLoanKind == uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2)
                    || flashLoanKind == uint(ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3)
            ) {
                // --------------- Flash loan Uniswap V3. The strategy should support IUniswapV3FlashCallback
                // ensure that the vault has available amount
                uint balance = IERC20(flashAssets[0]).balanceOf(address(flashLoanVault));
                require(balance >= flashAmounts[0], InsufficientFlashBalance(balance, flashAmounts[0]));

                bool isToken0 = IUniswapV3PoolImmutables(flashLoanVault).token0() == flashAssets[0];
                IUniswapV3PoolActions(flashLoanVault).flash(
                    address(this),
                    isToken0 ? flashAmounts[0] : 0,
                    isToken0 ? 0 : flashAmounts[0],
                    abi.encode(flashAssets[0], flashAmounts[0], isToken0, userData)
                );
            } else {
                // --------------- Default flash loan Balancer v2, paid. The strategy should support IFlashLoanRecipient
                IBVault(flashLoanVault).flashLoan(address(this), flashAssets, flashAmounts, userData);
            }
        }
    }

    /// @notice Process received flash loan
    /// @param token Address of the token received in flash loan. This is the debt asset.
    /// @param amount Amount of the token received in flash loan = a part of the user debt to be paid in liquidation
    /// @param fee Fee of the flash loan (if any)
    /// @param userData User data passed to the callback
    function receiveFlashLoan(
        address platform,
        LiquidationBotStorage storage $,
        address token,
        uint amount,
        uint fee,
        bytes memory userData
    ) internal {
        address flashLoanVault = $.flashLoanVault;
        require(msg.sender == flashLoanVault, UnauthorizedCallback());

        UserData memory data = abi.decode(userData, (UserData));

        if ($.wrappedMetaVaults[data.collateralAsset] != 0) {
            IMetaVault metaVault = IMetaVault(IWrappedMetaVault(data.collateralAsset).metaVault());
            metaVault.setLastBlockDefenseDisabledTx(
                uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1)
            );

            // Swap of meta-vault-tokens take a lot of gas. We can use cache to reduce gas
            //            priceReader_.preCalculatePriceTx(address(metaVault));
            //            metaVault.cachePrices(false);
        }

        // --------------- make liquidation: pay debt partially, receive collateral on balance
        uint collateralToSwap = _liquidateUser(data);

        // --------------- swap collateral asset to the debt asset
        _swap(platform, data.collateralAsset, data.debtAsset, collateralToSwap, priceImpactTolerance($));

        // --------------- return flash loan + fee back to the vault
        uint balance = IERC20(data.debtAsset).balanceOf(address(this));

        require(balance >= amount + fee, InsufficientBalanceToPayFlash(balance, amount + fee));

        IERC20(token).safeTransfer(flashLoanVault, amount + fee);

        if ($.wrappedMetaVaults[data.collateralAsset] != 0) {
            IMetaVault(IWrappedMetaVault(data.collateralAsset).metaVault()).setLastBlockDefenseDisabledTx(
                uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0)
            );
        }
    }
    //endregion -------------------------------------- Flash loan

    //region -------------------------------------- Internal logic
    /// @notice Sell tokenIn for tokenOut
    /// @param tokenIn Swap input token
    /// @param tokenOut Swap output token
    /// @param amount Amount of tokenIn for swap.
    /// @param priceImpactTolerance_ Price impact tolerance. Must include fees at least. Denominator is 100_000.
    function _swap(
        address platform,
        address tokenIn,
        address tokenOut,
        uint amount,
        uint priceImpactTolerance_
    ) internal {
        ISwapper swapper = ISwapper(IPlatform(platform).swapper());
        IERC20(tokenIn).forceApprove(address(swapper), amount);
        swapper.swap(tokenIn, tokenOut, amount, priceImpactTolerance_);
    }

    /// @notice Send {amount} of {asset_} to the registered {profitTarget}
    function _sendProfit(LiquidationBotStorage storage $, address user, address asset_, uint amount) internal {
        address profitTarget = $.profitTarget;
        if (profitTarget != address(0) && amount != 0) {
            IERC20(asset_).safeTransfer(profitTarget, amount);
            emit Profit(user, asset_, amount, profitTarget);
        }
    }

    /// @notice Get user position (first collateral and first debt found)
    function _getUserPosition(
        address user,
        IAaveDataProvider dataProvider
    ) internal view returns (ILiquidationBot.UserPosition memory) {
        IAaveDataProvider.TokenData[] memory tokensData = dataProvider.getAllReservesTokens();
        uint len = tokensData.length;
        ILiquidationBot.UserPosition memory dest;
        for (uint i; i < len; ++i) {
            (uint currentATokenBalance, uint currentStableDebt, uint currentVariableDebt,,,,,,) =
                dataProvider.getUserReserveData(tokensData[i].tokenAddress, user);

            if (currentATokenBalance != 0 && dest.collateralReserve == address(0)) {
                dest.collateralReserve = tokensData[i].tokenAddress;
                dest.collateralAmount = currentATokenBalance;
            }

            if ((currentStableDebt != 0 || currentVariableDebt != 0) && dest.debtReserve == address(0)) {
                dest.debtReserve = tokensData[i].tokenAddress;
                dest.debtAmount = currentStableDebt + currentVariableDebt;
            }

            if (dest.collateralAmount != 0 && dest.debtAmount != 0) {
                break;
            }
        }

        return dest;
    }

    /// @notice Make liquidation: pay debt partially, receive collateral on balance.
    /// @dev As result the contract should receive {getCollateralToReceive(...)} of {collateralAsset} on balance
    /// @return balanceAfter Balance of the collateral asset after liquidation
    function _liquidateUser(UserData memory data) internal returns (uint) {
        AaveContracts memory ac = getAaveContracts(data.aavePool);

        IERC20(data.debtAsset).forceApprove(address(ac.pool), data.repayAmount);

        uint balanceBefore = IERC20(data.collateralAsset).balanceOf(address(this));
        ac.pool.liquidationCall(data.collateralAsset, data.debtAsset, data.user, data.repayAmount, false);
        uint balanceAfter = IERC20(data.collateralAsset).balanceOf(address(this));

        emit OnLiquidation(
            data.aavePool, data.user, data.repayAmount, balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0
        );

        return balanceAfter;
    }

    /// @notice Calculate amount of debt that should be repaid during liquidation
    /// @param targetHealthFactor_ if 0 then max possible debt should be repaid (up to 50% of total debt)
    function _getRepayAmount(
        AaveContracts memory ac,
        address collateralAsset_,
        address debtAsset_,
        ILiquidationBot.UserAccountData memory userAccountData_,
        uint targetHealthFactor_
    ) internal view returns (uint repayAmount) {
        ReserveData memory rdDebt = _getReserveData(ac, debtAsset_);
        ReserveData memory rdCollateral = _getReserveData(ac, collateralAsset_);

        // We can take max 50% of the total debt
        uint maxRepayBase = (userAccountData_.totalDebtBase * 5_000) / 10_000;

        // Calculate repayment amount required to get target health factor after liquidation
        uint repayAmountBase =
            _getRepayAmountBaseForHealthFactor(userAccountData_, rdCollateral, targetHealthFactor_, maxRepayBase);

        return _fromBase(ac, rdDebt, repayAmountBase);
    }

    /// @notice Calculate the repayment amount needed to reach the target health factor after liquidation
    /// @dev This function accounts for the fact that liquidation reduces both debt AND collateral
    /// @param userAccountData_ Current user account data (collateral, debt, HF, etc.)
    /// @param rdCollateral Reserve data for the collateral asset (includes liquidation bonus)
    /// @param targetHealthFactor_ Desired health factor after liquidation (in 1e18, must be > 1e18)
    /// @param maxRepayBase Maximum allowed repayment in base currency (typically 50% of total debt)
    /// @return repayAmountBase Amount to repay in base currency units
    function _getRepayAmountBaseForHealthFactor(
        ILiquidationBot.UserAccountData memory userAccountData_,
        ReserveData memory rdCollateral,
        uint targetHealthFactor_,
        uint maxRepayBase
    ) internal pure returns (uint repayAmountBase) {
        if (targetHealthFactor_ == 0) {
            return maxRepayBase;
        }

        // Current values from user account
        // C = userAccountData_.totalCollateralBase;  // Total collateral in base currency
        // D = userAccountData_.totalDebtBase;        // Total debt in base currency
        // LT = userAccountData_.currentLiquidationThreshold;  // Liquidation threshold in basis points (e.g., 9850 = 98.5%)
        // bonus = rdCollateral.liquidationBonus;     // Liquidation bonus in basis points (e.g., 10150 = 101.5%)
        //
        // Health Factor formula: HF = (Collateral * LiquidationThreshold / 10000) / Debt
        // After liquidation with repayment R:
        // - New debt: D - R
        // - Collateral seized from user: R * bonus / 10000
        // - New collateral: C - R * bonus / 10000
        // New HF = ((C - R * bonus / 10000) * LT / 10000) / (D - R)
        // R = (C * LT - D * HF) / (bonus * LT / 10000 - HF)

        // Scale down targetHF from 1e18 to 1e4 to match LT units
        // This avoids overflow and keeps all values in basis points
        uint targetHealthFactorBase = targetHealthFactor_ / 1e14;

        // Calculate numerator: C*LT - D*targetHF_scaled
        int numerator = int(userAccountData_.totalCollateralBase * userAccountData_.currentLiquidationThreshold)
            - int(userAccountData_.totalDebtBase * targetHealthFactorBase);

        // Calculate denominator: bonus*LT/10000 - targetHF_scaled
        int denominator = int(rdCollateral.liquidationBonus * userAccountData_.currentLiquidationThreshold / 10_000)
            - int(targetHealthFactorBase);

        if (numerator * denominator <= 0) {
            repayAmountBase = maxRepayBase; // target unachievable (e.g., too high, would require negative R)
        } else {
            uint absNum = uint(numerator < 0 ? -numerator : numerator);
            uint absDen = uint(denominator < 0 ? -denominator : denominator);
            repayAmountBase = Math.mulDiv(absNum, 1e18, absDen) / 1e18;
        }

        // Cap at maximum allowed repayment (50% of debt)
        if (repayAmountBase > maxRepayBase) {
            repayAmountBase = maxRepayBase;
        }

        return repayAmountBase;
    }

    /// @notice How much of {collateralAsset_} the bot will receive if it repays {repayAmount_} of {debtAsset_}
    /// in assumption that the user has {collateralAmount_} of collateral
    function getCollateralToReceive(
        AaveContracts memory ac,
        address collateralAsset_,
        address debtAsset_,
        uint collateralAmount_,
        uint repayAmount_
    ) internal view returns (uint collateralToReceive) {
        uint repayAmountBase = _toBase(ac, _getReserveData(ac, debtAsset_), repayAmount_);

        ReserveData memory rdCollateral = _getReserveData(ac, collateralAsset_);
        uint collateralAmountBase = _toBase(ac, rdCollateral, collateralAmount_);

        // typical value of liquidationBonus is 10150 (1.5% bonus)
        uint collateralToReceiveBase = repayAmountBase * rdCollateral.liquidationBonus / 10_000;

        uint fee = ac.dataProvider.getLiquidationProtocolFee(collateralAsset_);
        uint bonusPart = collateralToReceiveBase - repayAmountBase;
        uint bonusAfterFee = bonusPart * (10_000 - fee) / 10_000;
        collateralToReceiveBase = repayAmountBase + bonusAfterFee;

        if (collateralToReceiveBase > collateralAmountBase) {
            collateralToReceiveBase = collateralAmountBase;
        }

        return _fromBase(ac, rdCollateral, collateralToReceiveBase);
    }

    //endregion -------------------------------------- Internal logic

    //region -------------------------------------- View
    function priceImpactTolerance(LiquidationBotStorage storage $) internal view returns (uint _priceImpactTolerance) {
        _priceImpactTolerance = $.priceImpactTolerance;
        return _priceImpactTolerance == 0 ? DEFAULT_SWAP_PRICE_IMPACT_TOLERANCE : _priceImpactTolerance;
    }

    //endregion -------------------------------------- View

    //region -------------------------------------- Utils
    function getAaveContracts(address aavePool_) internal view returns (AaveContracts memory ac) {
        ac.pool = IPool(aavePool_);
        IAaveAddressProvider addressProvider = IAaveAddressProvider(ac.pool.ADDRESSES_PROVIDER());
        ac.dataProvider = IAaveDataProvider(addressProvider.getPoolDataProvider());
        ac.oracle = IAavePriceOracle(addressProvider.getPriceOracle());
        return ac;
    }

    function _toBase(AaveContracts memory ac, ReserveData memory rd, uint amount) internal view returns (uint) {
        uint price = ac.oracle.getAssetPrice(rd.asset);
        return (amount * price) / (10 ** rd.decimals);
    }

    function _fromBase(AaveContracts memory ac, ReserveData memory rd, uint amountBase) internal view returns (uint) {
        uint price = ac.oracle.getAssetPrice(rd.asset);
        return (amountBase * (10 ** rd.decimals)) / price;
    }

    function _getReserveData(AaveContracts memory ac, address asset) internal view returns (ReserveData memory) {
        ReserveData memory rd;
        (rd.decimals, rd.ltv, rd.liquidationThreshold, rd.liquidationBonus,,,,,,) =
            ac.dataProvider.getReserveConfigurationData(asset);
        rd.asset = asset;

        return rd;
    }

    function getUserAccountData(
        AaveContracts memory ac,
        address user
    ) internal view returns (ILiquidationBot.UserAccountData memory) {
        ILiquidationBot.UserAccountData memory userData;

        (
            userData.totalCollateralBase,
            userData.totalDebtBase,
            userData.availableBorrowsBase,
            userData.currentLiquidationThreshold,
            userData.ltv,
            userData.healthFactor
        ) = ac.pool.getUserAccountData(user);

        return userData;
    }

    function getUserAssetInfo(
        address aavePool,
        address user
    ) internal view returns (ILiquidationBot.UserAssetInfo[] memory infos) {
        IAaveDataProvider dataProvider = getAaveContracts(aavePool).dataProvider;
        IAaveDataProvider.TokenData[] memory tokensData = dataProvider.getAllReservesTokens();

        uint len = tokensData.length;
        ILiquidationBot.UserAssetInfo[] memory temp = new ILiquidationBot.UserAssetInfo[](len);

        uint count;
        for (uint i; i < len; ++i) {
            (uint currentATokenBalance,, uint currentVariableDebt,,,,,,) =
                dataProvider.getUserReserveData(tokensData[i].tokenAddress, user);

            if (currentATokenBalance != 0 || currentVariableDebt != 0) {
                temp[count] = ILiquidationBot.UserAssetInfo({
                    asset: tokensData[i].tokenAddress,
                    currentATokenBalance: currentATokenBalance,
                    currentVariableDebt: currentVariableDebt
                });
                ++count;
            }
        }

        if (count == len) {
            infos = temp;
        } else {
            infos = new ILiquidationBot.UserAssetInfo[](count);
            for (uint i; i < count; ++i) {
                infos[i] = temp[i];
            }
        }

        return infos;
    }

    function getLiquidationBotStorage() internal pure returns (LiquidationBotStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _LIQUIDATION_BOT_STORAGE_LOCATION
        }
    }

    function _getUserData(
        address aavePool,
        address users,
        ILiquidationBot.UserPosition memory position,
        uint repayAmount
    ) internal pure returns (UserData memory) {
        return UserData({
            aavePool: aavePool,
            user: users,
            collateralAsset: position.collateralReserve,
            debtAsset: position.debtReserve,
            collateralAmount: position.collateralAmount,
            repayAmount: repayAmount
        });
    }

    //endregion -------------------------------------- Utils
}
