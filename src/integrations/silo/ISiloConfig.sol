// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ISilo} from "./ISilo.sol";

interface ISiloConfig {
    struct InitData {
        /// @notice Can be address zero if deployer fees are not to be collected. If deployer address is zero then
        /// deployer fee must be zero as well. Deployer will be minted an NFT that gives the right to claim deployer
        /// fees. NFT can be transferred with the right to claim.
        address deployer;
        /// @notice Address of the hook receiver called on every before/after action on Silo. Hook contract also
        /// implements liquidation logic and veSilo gauge connection.
        address hookReceiver;
        /// @notice Deployer's fee in 18 decimals points. Deployer will earn this fee based on the interest earned
        /// by the Silo. Max deployer fee is set by the DAO. At deployment it is 15%.
        uint deployerFee;
        /// @notice DAO's fee in 18 decimals points. DAO will earn this fee based on the interest earned
        /// by the Silo. Acceptable fee range fee is set by the DAO. Default at deployment is 5% - 50%.
        uint daoFee;
        /// @notice Address of the first token
        address token0;
        /// @notice Address of the solvency oracle. Solvency oracle is used to calculate LTV when deciding if borrower
        /// is solvent or should be liquidated. Solvency oracle is optional and if not set price of 1 will be assumed.
        address solvencyOracle0;
        /// @notice Address of the maxLtv oracle. Max LTV oracle is used to calculate LTV when deciding if borrower
        /// can borrow given amount of assets. Max LTV oracle is optional and if not set it defaults to solvency
        /// oracle. If neither is set price of 1 will be assumed.
        address maxLtvOracle0;
        /// @notice Address of the interest rate model
        address interestRateModel0;
        /// @notice Maximum LTV for first token. maxLTV is in 18 decimals points and is used to determine, if borrower
        /// can borrow given amount of assets. MaxLtv is in 18 decimals points. MaxLtv must be lower or equal to LT.
        uint maxLtv0;
        /// @notice Liquidation threshold for first token. LT is used to calculate solvency. LT is in 18 decimals
        /// points. LT must not be lower than maxLTV.
        uint lt0;
        /// @notice minimal acceptable LTV after liquidation, in 18 decimals points
        uint liquidationTargetLtv0;
        /// @notice Liquidation fee for the first token in 18 decimals points. Liquidation fee is what liquidator earns
        /// for repaying insolvent loan.
        uint liquidationFee0;
        /// @notice Flashloan fee sets the cost of taking a flashloan in 18 decimals points
        uint flashloanFee0;
        /// @notice Indicates if a beforeQuote on oracle contract should be called before quoting price
        bool callBeforeQuote0;
        /// @notice Address of the second token
        address token1;
        /// @notice Address of the solvency oracle. Solvency oracle is used to calculate LTV when deciding if borrower
        /// is solvent or should be liquidated. Solvency oracle is optional and if not set price of 1 will be assumed.
        address solvencyOracle1;
        /// @notice Address of the maxLtv oracle. Max LTV oracle is used to calculate LTV when deciding if borrower
        /// can borrow given amount of assets. Max LTV oracle is optional and if not set it defaults to solvency
        /// oracle. If neither is set price of 1 will be assumed.
        address maxLtvOracle1;
        /// @notice Address of the interest rate model
        address interestRateModel1;
        /// @notice Maximum LTV for first token. maxLTV is in 18 decimals points and is used to determine,
        /// if borrower can borrow given amount of assets. maxLtv is in 18 decimals points
        uint maxLtv1;
        /// @notice Liquidation threshold for first token. LT is used to calculate solvency. LT is in 18 decimals points
        uint lt1;
        /// @notice minimal acceptable LTV after liquidation, in 18 decimals points
        uint liquidationTargetLtv1;
        /// @notice Liquidation fee is what liquidator earns for repaying insolvent loan.
        uint liquidationFee1;
        /// @notice Flashloan fee sets the cost of taking a flashloan in 18 decimals points
        uint flashloanFee1;
        /// @notice Indicates if a beforeQuote on oracle contract should be called before quoting price
        bool callBeforeQuote1;
    }

    struct ConfigData {
        uint daoFee;
        uint deployerFee;
        address silo;
        address token;
        address protectedShareToken;
        address collateralShareToken;
        address debtShareToken;
        address solvencyOracle;
        address maxLtvOracle;
        address interestRateModel;
        uint maxLtv;
        uint lt;
        uint liquidationTargetLtv;
        uint liquidationFee;
        uint flashloanFee;
        address hookReceiver;
        bool callBeforeQuote;
    }

    struct DepositConfig {
        address silo;
        address token;
        address collateralShareToken;
        address protectedShareToken;
        uint daoFee;
        uint deployerFee;
        address interestRateModel;
    }

    error OnlySilo();
    error OnlySiloOrTokenOrHookReceiver();
    error WrongSilo();
    error OnlyDebtShareToken();
    error DebtExistInOtherSilo();
    error FeeTooHigh();

    /// @dev It should be called on debt transfer (debt share token transfer).
    /// In the case if the`_recipient` doesn't have configured a collateral silo,
    /// it will be set to the collateral silo of the `_sender`.
    /// @param _sender sender address
    /// @param _recipient recipient address
    function onDebtTransfer(address _sender, address _recipient) external;

    /// @notice Set collateral silo.
    /// @dev Revert if msg.sender is not a SILO_0 or SILO_1.
    /// @dev Always set collateral silo the same as msg.sender.
    /// @param _borrower borrower address
    function setThisSiloAsCollateralSilo(address _borrower) external;

    /// @notice Set collateral silo
    /// @dev Revert if msg.sender is not a SILO_0 or SILO_1.
    /// @dev Always set collateral silo opposite to the msg.sender.
    /// @param _borrower borrower address
    function setOtherSiloAsCollateralSilo(address _borrower) external;

    /// @notice Accrue interest for the silo
    /// @param _silo silo for which accrue interest
    function accrueInterestForSilo(address _silo) external;

    /// @notice Accrue interest for both silos (SILO_0 and SILO_1 in a config)
    function accrueInterestForBothSilos() external;

    /// @notice Retrieves the collateral silo for a specific borrower.
    /// @dev As a user can deposit into `Silo0` and `Silo1`, this property specifies which Silo
    /// will be used as collateral for the debt. Later on, it will be used for max LTV and solvency checks.
    /// After being set, the collateral silo is never set to `address(0)` again but such getters as
    /// `getConfigsForSolvency`, `getConfigsForBorrow`, `getConfigsForWithdraw` will return empty
    /// collateral silo config if borrower doesn't have debt.
    ///
    /// In the SiloConfig collateral silo is set by the following functions:
    /// `onDebtTransfer` - only if the recipient doesn't have collateral silo set (inherits it from the sender)
    /// This function is called on debt share token transfer (debt transfer).
    /// `setThisSiloAsCollateralSilo` - sets the same silo as the one that calls the function.
    /// `setOtherSiloAsCollateralSilo` - sets the opposite silo as collateral from the one that calls the function.
    ///
    /// In the Silo collateral silo is set by the following functions:
    /// `borrow` - always sets opposite silo as collateral.
    /// If Silo0 borrows, then Silo1 will be collateral and vice versa.
    /// `borrowSameAsset` - always sets the same silo as collateral.
    /// `switchCollateralToThisSilo` - always sets the same silo as collateral.
    /// @param _borrower The address of the borrower for which the collateral silo is being retrieved
    /// @return collateralSilo The address of the collateral silo for the specified borrower
    function borrowerCollateralSilo(address _borrower) external view returns (address collateralSilo);

    /// @notice Retrieves the silo ID
    /// @dev Each silo is assigned a unique ID. ERC-721 token is minted with identical ID to deployer.
    /// An owner of that token receives the deployer fees.
    /// @return siloId The ID of the silo
    function SILO_ID() external view returns (uint siloId); // solhint-disable-line func-name-mixedcase

    /// @notice Retrieves the addresses of the two silos
    /// @return silo0 The address of the first silo
    /// @return silo1 The address of the second silo
    function getSilos() external view returns (address silo0, address silo1);

    /// @notice Retrieves the asset associated with a specific silo
    /// @dev This function reverts for incorrect silo address input
    /// @param _silo The address of the silo for which the associated asset is being retrieved
    /// @return asset The address of the asset associated with the specified silo
    function getAssetForSilo(address _silo) external view returns (address asset);

    /// @notice Verifies if the borrower has debt in other silo by checking the debt share token balance
    /// @param _thisSilo The address of the silo in respect of which the debt is checked
    /// @param _borrower The address of the borrower for which the debt is checked
    /// @return hasDebt true if the borrower has debt in other silo
    function hasDebtInOtherSilo(address _thisSilo, address _borrower) external view returns (bool hasDebt);

    /// @notice Retrieves the debt silo associated with a specific borrower
    /// @dev This function reverts if debt present in two silo (should not happen)
    /// @param _borrower The address of the borrower for which the debt silo is being retrieved
    function getDebtSilo(address _borrower) external view returns (address debtSilo);

    /// @notice Retrieves configuration data for both silos. First config is for the silo that is asking for configs.
    /// @param borrower borrower address for which debtConfig will be returned
    /// @return collateralConfig The configuration data for collateral silo (empty if there is no debt).
    /// @return debtConfig The configuration data for debt silo (empty if there is no debt).
    function getConfigsForSolvency(address borrower)
        external
        view
        returns (ConfigData memory collateralConfig, ConfigData memory debtConfig);

    /// @notice Retrieves configuration data for a specific silo
    /// @dev This function reverts for incorrect silo address input.
    /// @param _silo The address of the silo for which configuration data is being retrieved
    /// @return config The configuration data for the specified silo
    function getConfig(address _silo) external view returns (ConfigData memory config);

    /// @notice Retrieves configuration data for a specific silo for withdraw fn.
    /// @dev This function reverts for incorrect silo address input.
    /// @param _silo The address of the silo for which configuration data is being retrieved
    /// @return depositConfig The configuration data for the specified silo (always config for `_silo`)
    /// @return collateralConfig The configuration data for the collateral silo (empty if there is no debt)
    /// @return debtConfig The configuration data for the debt silo (empty if there is no debt)
    function getConfigsForWithdraw(
        address _silo,
        address _borrower
    )
        external
        view
        returns (DepositConfig memory depositConfig, ConfigData memory collateralConfig, ConfigData memory debtConfig);

    /// @notice Retrieves configuration data for a specific silo for borrow fn.
    /// @dev This function reverts for incorrect silo address input.
    /// @param _debtSilo The address of the silo for which configuration data is being retrieved
    /// @return collateralConfig The configuration data for the collateral silo (always other than `_debtSilo`)
    /// @return debtConfig The configuration data for the debt silo (always config for `_debtSilo`)
    function getConfigsForBorrow(address _debtSilo)
        external
        view
        returns (ConfigData memory collateralConfig, ConfigData memory debtConfig);

    /// @notice Retrieves fee-related information for a specific silo
    /// @dev This function reverts for incorrect silo address input
    /// @param _silo The address of the silo for which fee-related information is being retrieved.
    /// @return daoFee The DAO fee percentage in 18 decimals points.
    /// @return deployerFee The deployer fee percentage in 18 decimals points.
    /// @return flashloanFee The flashloan fee percentage in 18 decimals points.
    /// @return asset The address of the asset associated with the specified silo.
    function getFeesWithAsset(address _silo)
        external
        view
        returns (uint daoFee, uint deployerFee, uint flashloanFee, address asset);

    /// @notice Retrieves share tokens associated with a specific silo
    /// @dev This function reverts for incorrect silo address input
    /// @param _silo The address of the silo for which share tokens are being retrieved
    /// @return protectedShareToken The address of the protected (non-borrowable) share token
    /// @return collateralShareToken The address of the collateral share token
    /// @return debtShareToken The address of the debt share token
    function getShareTokens(address _silo)
        external
        view
        returns (address protectedShareToken, address collateralShareToken, address debtShareToken);

    /// @notice Retrieves the share token and the silo token associated with a specific silo
    /// @param _silo The address of the silo for which the share token and silo token are being retrieved
    /// @param _collateralType The type of collateral
    /// @return shareToken The address of the share token (collateral or protected collateral)
    /// @return asset The address of the silo token
    function getCollateralShareTokenAndAsset(
        address _silo,
        ISilo.CollateralType _collateralType
    ) external view returns (address shareToken, address asset);

    /// @notice Retrieves the share token and the silo token associated with a specific silo
    /// @param _silo The address of the silo for which the share token and silo token are being retrieved
    /// @return shareToken The address of the share token (debt)
    /// @return asset The address of the silo token
    function getDebtShareTokenAndAsset(address _silo) external view returns (address shareToken, address asset);
}
