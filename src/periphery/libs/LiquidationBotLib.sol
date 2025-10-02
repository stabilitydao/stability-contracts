// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IAaveAddressProvider} from "../../integrations/aave/IAaveAddressProvider.sol";
import {IAaveDataProvider} from "../../integrations/aave/IAaveDataProvider.sol";
import {IAavePriceOracle} from "../../integrations/aave/IAavePriceOracle.sol";
import {IBVault} from "../../integrations/balancer/IBVault.sol";
import {IControllable} from "../../interfaces/IControllable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILeverageLendingStrategy} from "../../interfaces/ILeverageLendingStrategy.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IPool} from "../../integrations/aave/IPool.sol";
import {IUniswapV3PoolActions} from "../../integrations/uniswapv3/pool/IUniswapV3PoolActions.sol";
import {IUniswapV3PoolImmutables} from "../../integrations/uniswapv3/pool/IUniswapV3PoolImmutables.sol";
import {IVaultMainV3} from "../../integrations/balancerv3/IVaultMainV3.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library LiquidationBotLib {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.LiquidationBot")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant _LIQUIDATION_BOT_STORAGE_LOCATION = 0; // todo

    uint internal constant DEFAULT_SWAP_PRICE_IMPACT_TOLERANCE = 1_000;

    //region -------------------------------------- Data types

    error UnauthorizedCallback();
    error NotWhitelisted();
    error IncorrectAmountReceived(address asset, uint balanceBefore, uint balanceAfter, uint expectedAmount);
    error InsufficientBalance(uint availableBalance, uint requiredBalance);

    event Liquidation(
        address user,
        UserAccountData userDataBefore,
        UserAccountData userDataAfter,
        address debtAsset,
        uint debtRepaid,
        address collateralAsset,
        uint collateralReceived,
        uint amountToProfitTarget
    );
    event Profit(address fromUser, address asset, uint amount, address targetProfit);
    event UserSkipped(address user, UserAccountData userData, UserPosition position);

    event SetFlashLoan(address vault, uint kind);
    event SetPriceImpactTolerance(uint priceImpactTolerance);
    event SetProfitTarget(address profitTarget);
    event Whitelist(address operator, bool add);

    /// @custom:storage-location erc7201:stability.LiquidationBot
    struct LiquidationBotStorage {
        /// @notice Whitelisted operators that can call main actions
        mapping(address operator => bool allowed) whitelistOperators;
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
    }

    struct UserPosition {
        address collateralReserve;
        address debtReserve;
        uint collateralAmount;
        uint debtAmount;
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

    struct UserAccountData {
        uint totalCollateralBase;
        uint totalDebtBase;
        uint availableBorrowsBase;
        uint currentLiquidationThreshold;
        uint ltv;
        uint healthFactor;
    }

    struct UserData {
        address aaveAddressProvider;
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
    /// @param addressProvider AAVE 3.0.2 address provider.
    /// @param users List of users to liquidate (users with health factor < 1)
    function liquidate(address addressProvider, address[] memory users) internal {
        LiquidationBotStorage storage $ = getLiquidationBotStorage();
        AaveContracts memory ac = _getAaveContracts(addressProvider);

        uint len = users.length;
        for (uint i; i < len; ++i) {
            UserAccountData memory userData0 = _getUserAccountData(ac, users[i]);
            UserPosition memory position = _getUserPosition(users[i], ac.dataProvider);

            if (
                userData0.healthFactor >= 1e18 || position.collateralReserve == address(0)
                    || position.debtReserve == address(0)
            ) {
                emit UserSkipped(users[i], userData0, position);
            } else {
                uint repayAmount = _getRepayAmount(ac, position, userData0.totalDebtBase);
                uint balanceBefore = IERC20(position.debtReserve).balanceOf(address(this));

                _requestFlashLoanExplicit(
                    $.flashLoanKind,
                    $.flashLoanVault,
                    position.debtReserve,
                    repayAmount,
                    abi.encode(_getUserData(addressProvider, users[i], position, repayAmount))
                );

                uint balanceAfter = IERC20(position.debtReserve).balanceOf(address(this));
                uint collateralReceived = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;

                _sendProfit($, users[i], position.debtReserve, balanceAfter);

                UserAccountData memory userData1 = _getUserAccountData(ac, users[i]);

                emit Liquidation(
                    users[i],
                    userData0,
                    userData1,
                    position.debtReserve,
                    position.debtAmount,
                    position.collateralReserve,
                    collateralReceived,
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

    function changeWhitelist(address operator_, bool add_) internal {
        LiquidationBotStorage storage $ = getLiquidationBotStorage();
        $.whitelistOperators[operator_] = add_;

        emit Whitelist(operator_, add_);
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
                require(
                    IERC20(flashAssets[0]).balanceOf(address(flashLoanVault)) >= flashAmounts[0],
                    IControllable.InsufficientBalance()
                );

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

        // --------------- make liquidation: pay debt partially, receive collateral on balance
        _liquidateUser(data);

        // --------------- swap collateral asset to the debt asset
        _swap(platform, data.collateralAsset, data.debtAsset, amount, priceImpactTolerance($));

        // --------------- return flash loan + fee back to the vault
        uint balance = IERC20(data.debtAsset).balanceOf(address(this));
        require(balance >= amount + fee, InsufficientBalance(balance, amount + fee));

        IERC20(token).safeTransfer(flashLoanVault, amount + fee);
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
    ) internal view returns (UserPosition memory) {
        IAaveDataProvider.TokenData[] memory tokensData = dataProvider.getAllReservesTokens();
        uint len = tokensData.length;
        UserPosition memory dest;
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
    /// Ensure that we receive expected amount of collateral
    /// @return collateralBalance New balance of the collateral asset on the contract after liquidation
    function _liquidateUser(UserData memory data) internal returns (uint collateralBalance) {
        AaveContracts memory ac = _getAaveContracts(data.aaveAddressProvider);
        uint collateralToReceive =
            _getCollateralToReceive(ac, data.collateralAsset, data.debtAsset, data.collateralAmount, data.repayAmount);

        uint amountBefore = IERC20(data.collateralAsset).balanceOf(address(this));
        IERC20(data.debtAsset).forceApprove(address(ac.pool), data.repayAmount);

        ac.pool.liquidationCall(data.collateralAsset, data.debtAsset, data.user, data.repayAmount, false);

        collateralBalance = IERC20(data.collateralAsset).balanceOf(address(this));
        require(
            collateralBalance > amountBefore && collateralBalance - amountBefore == collateralToReceive,
            IncorrectAmountReceived(data.collateralAsset, amountBefore, collateralBalance, collateralToReceive)
        );
    }

    /// @notice Calculate amount of debt that should be repaid during liquidation
    function _getRepayAmount(
        AaveContracts memory ac,
        UserPosition memory pos_,
        uint totalDebtBase_
    ) internal view returns (uint repayAmount) {
        ReserveData memory rdDebt = _getReserveData(ac, pos_.debtReserve);

        // todo We can take max 50% of the total debt. Should we try to use less values?
        uint maxRepayAmountBase = totalDebtBase_ * 4_999 / 10_000;
        uint debtAmountBase = _toBase(ac, rdDebt, pos_.debtAmount);

        uint repayAmountBase = debtAmountBase < maxRepayAmountBase ? debtAmountBase : maxRepayAmountBase;
        repayAmount = _fromBase(ac, rdDebt, repayAmountBase);
    }

    function _getCollateralToReceive(
        AaveContracts memory ac,
        address collateralAsset_,
        address debtAsset_,
        uint collateralAmount_,
        uint repayAmount_
    ) internal view returns (uint) {
        uint repayAmountBase = _toBase(ac, _getReserveData(ac, debtAsset_), repayAmount_);

        ReserveData memory rdCollateral = _getReserveData(ac, collateralAsset_);
        uint collateralAmountBase = _toBase(ac, rdCollateral, collateralAmount_);

        // typical value of liquidationBonus is 10150 (1.5% bonus)
        uint collateralToReceiveBase = repayAmountBase * rdCollateral.liquidationBonus / 10_000;
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
    function _getAaveContracts(address addressProvider_) internal view returns (AaveContracts memory ac) {
        ac.pool = IPool(IAaveAddressProvider(addressProvider_).getPool());
        ac.dataProvider = IAaveDataProvider(IAaveAddressProvider(addressProvider_).getPoolDataProvider());
        ac.oracle = IAavePriceOracle(IAaveAddressProvider(addressProvider_).getPriceOracle());
        return ac;
    }

    function _toBase(AaveContracts memory ac, ReserveData memory rd, uint amount) internal view returns (uint) {
        uint price = ac.oracle.getAssetPrice(rd.asset);
        return (amount * price) / (10 ** rd.decimals);
    }

    function _fromBase(AaveContracts memory ac, ReserveData memory rd, uint amount) internal view returns (uint) {
        uint price = ac.oracle.getAssetPrice(rd.asset);
        return (amount * (10 ** rd.decimals)) / price;
    }

    function _getReserveData(AaveContracts memory ac, address asset) internal view returns (ReserveData memory rd) {
        (rd.decimals, rd.ltv, rd.liquidationThreshold, rd.liquidationBonus,,,,,,) =
            ac.dataProvider.getReserveConfigurationData(asset);
        rd.asset = asset;

        return rd;
    }

    function _getUserAccountData(
        AaveContracts memory ac,
        address user
    ) internal view returns (UserAccountData memory userData) {
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

    function getLiquidationBotStorage() internal pure returns (LiquidationBotStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _LIQUIDATION_BOT_STORAGE_LOCATION
        }
    }

    function _getUserData(
        address addressProvider,
        address users,
        UserPosition memory position,
        uint repayAmount
    ) internal pure returns (UserData memory) {
        return UserData({
            aaveAddressProvider: addressProvider,
            user: users,
            collateralAsset: position.collateralReserve,
            debtAsset: position.debtReserve,
            collateralAmount: position.collateralAmount,
            repayAmount: repayAmount
        });
    }

    //endregion -------------------------------------- Utils
}
