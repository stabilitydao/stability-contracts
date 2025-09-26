// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface ISilo is IERC4626 {
    error NotEnoughLiquidity();
    /// @dev There are 2 types of accounting in the system: for non-borrowable collateral deposit called "protected" and
    ///      for borrowable collateral deposit called "collateral". System does
    ///      identical calculations for each type of accounting but it uses different data. To avoid code duplication
    ///      this enum is used to decide which data should be read.
    enum CollateralType {
        Protected,
        Collateral
    }

    /// @notice Implements IERC4626.deposit for protected (non-borrowable) collateral and collateral
    /// @dev Reverts for debt asset type
    function deposit(uint _assets, address _receiver, CollateralType collateralType) external returns (uint shares);

    /// @notice Allows an address to borrow a specified amount of assets
    /// @param _assets Amount of assets to borrow
    /// @param _receiver Address receiving the borrowed assets
    /// @param _borrower Address responsible for the borrowed assets
    /// @return shares Amount of shares equivalent to the borrowed assets
    function borrow(uint _assets, address _receiver, address _borrower) external returns (uint shares);

    /// @notice Repays a given asset amount and returns the equivalent number of shares
    /// @param _assets Amount of assets to be repaid
    /// @param _borrower Address of the borrower whose debt is being repaid
    /// @return shares The equivalent number of shares for the provided asset amount
    function repay(uint _assets, address _borrower) external returns (uint shares);

    /// @notice Implements IERC4626.withdraw for protected (non-borrowable) collateral and collateral
    /// @dev Reverts for debt asset type
    function withdraw(
        uint _assets,
        address _receiver,
        address _owner,
        CollateralType collateralType
    ) external returns (uint shares);

    /// @notice Accrues interest for the asset and returns the accrued interest amount
    /// @return accruedInterest The total interest accrued during this operation
    function accrueInterest() external returns (uint accruedInterest);

    /// @inheritdoc IERC4626
    /// @dev For protected (non-borrowable) collateral and debt, use:
    /// `convertToAssets(uint256 _shares, AssetType _assetType)` with `AssetType.Protected` or `AssetType.Debt`
    function convertToAssets(uint _shares) external view returns (uint assets);

    function convertToAssets(uint256 _shares, CollateralType _assetType) external view returns (uint256 assets);

    function asset() external view returns (address assetTokenAddres);

    /// @notice Fetches the silo configuration contract
    /// @return siloConfig Address of the configuration contract associated with the silo
    function config() external view returns (address siloConfig);

    /// @notice Calculates the maximum amount of assets that can be borrowed by the given address
    /// @param _borrower Address of the potential borrower
    /// @return maxAssets Maximum amount of assets that the borrower can borrow, this value is underestimated
    /// That means, in some cases when you borrow maxAssets, you will be able to borrow again eg. up to 2wei
    /// Reason for underestimation is to return value that will not cause borrow revert
    function maxBorrow(address _borrower) external view returns (uint maxAssets);

    /// @notice Calculates the maximum amount an address can repay based on their debt shares
    /// @param _borrower Address of the borrower
    /// @return assets Maximum amount of assets the borrower can repay
    function maxRepay(address _borrower) external view returns (uint assets);

    function getLiquidity() external view returns (uint256 liquidity);

    function maxWithdraw(address _owner, CollateralType _collateralType) external view returns (uint256 maxAssets);
}
