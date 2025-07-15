// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStandardizedYieldAdapter} from "../integrations/pendle/IStandardizedYieldAdapter.sol";
import {IMetaVault} from "../interfaces/IMetaVault.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";

/// @notice Pendle SY-adapter for Stability Wrapped Meta Vault
/// @dev See https://pendle.notion.site/How-to-write-a-SY-adapter-A-guide-20e567a21d3780a0835ffa62fc22d23b
/// @author dvpublic (https://github.com/dvpublic)
contract PendleWrappedMetaVaultAdapter is IStandardizedYieldAdapter {
  using SafeERC20 for IERC20;
  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                         CONSTANTS                          */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  string public constant VERSION = "1.0.0";

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                         VARIABLES                          */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @inheritdoc IStandardizedYieldAdapter
  /// @dev Address of the underlying asset of Wrapped MetaVault, i.e. metaUSD or metaS
  address public immutable PIVOT_TOKEN;
  address public immutable owner;

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                         ERRORS                             */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
  error NotOwner();
  error ZeroAddress();
  error IncorrectToken();
  error MaxWithdrawExceeded();

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                         Initialization                     */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
  constructor (address metaVault_) {
    require(metaVault_ != address(0), ZeroAddress());
    PIVOT_TOKEN = metaVault_;
  }

  //region ---------------------------------- View
  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                         View                               */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
  /// @inheritdoc IStandardizedYieldAdapter
  function getAdapterTokensDeposit() external view returns (address[] memory tokens) {
    tokens = new address[](1);
    tokens[0] = IMetaVault(PIVOT_TOKEN).assetsForDeposit()[0];
  }

  /// @inheritdoc IStandardizedYieldAdapter
  function getAdapterTokensRedeem() external view returns (address[] memory tokens) {
    tokens = new address[](1);
    tokens[0] = IMetaVault(PIVOT_TOKEN).assetsForWithdraw()[0];
  }

  /// @inheritdoc IStandardizedYieldAdapter
  function previewConvertToDeposit(address tokenIn, uint256 amountTokenIn) external view returns (uint256 amountOut) {
    //------------------- ensure that the tokenIn is the asset of the meta vault
    address[] memory assetsForDeposit = IMetaVault(PIVOT_TOKEN).assetsForDeposit();
    require(tokenIn == assetsForDeposit[0], IncorrectToken());

    //------------------- convert asset amount to the amount of meta vault tokens that will be minted on deposit
    uint[] memory amountsMax = new uint[](1);
    amountsMax[0] = amountTokenIn;

    (, amountOut, ) = IMetaVault(PIVOT_TOKEN).previewDepositAssets(assetsForDeposit, amountsMax);
  }

  /// @inheritdoc IStandardizedYieldAdapter
  function previewConvertToRedeem(address tokenOut, uint256 amountPivotTokenIn) external view returns (
    uint256 amountOut
  ) {
    //------------------- ensure that the tokenOut is the asset of the meta vault
    address[] memory assetsForWithdraw = IMetaVault(PIVOT_TOKEN).assetsForWithdraw();
    require(tokenOut == assetsForWithdraw[0], IncorrectToken());

    //------------------- convert meta vault balance => USD amount => asset amount
    (uint priceMetaVaultToken,) = IMetaVault(PIVOT_TOKEN).price();
    IPriceReader priceReader = IPriceReader(IPlatform(IControllable(PIVOT_TOKEN).platform()).priceReader());
    (uint priceAsset, ) = priceReader.getPrice(tokenOut);

    return Math.mulDiv(amountPivotTokenIn, priceMetaVaultToken, priceAsset, Math.Rounding.Ceil);
  }
  //endregion ---------------------------------- View

  //region ---------------------------------- Write
  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                         Write                              */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @inheritdoc IStandardizedYieldAdapter
  /// @dev We don't check slippage here, assume that the slippage is checked by the caller.
  function convertToDeposit(address tokenIn, uint256 amountTokenIn) external returns (uint256 amountOut) {
    console.log("convertToDeposit.0");
    address[] memory assetsForDeposit = IMetaVault(PIVOT_TOKEN).assetsForDeposit();
    require(tokenIn == assetsForDeposit[0], IncorrectToken());

    // todo take into account maxDeposit

    uint[] memory amountsMax = new uint[](1);
    amountsMax[0] = amountTokenIn;

    IERC20(assetsForDeposit[0]).forceApprove(PIVOT_TOKEN, amountsMax[0]);

    uint balanceUserBefore = IMetaVault(PIVOT_TOKEN).balanceOf(msg.sender);
    console.log("convertToDeposit.1");
    // todo disable last-block defence
    IMetaVault(PIVOT_TOKEN).depositAssets(assetsForDeposit, amountsMax, 0, msg.sender);
    // todo enable last-block defence
    uint balanceAdapterAfter = IERC20(assetsForDeposit[0]).balanceOf(address(this));
    console.log("convertToDeposit.2");
    return IMetaVault(PIVOT_TOKEN).balanceOf(msg.sender) - balanceUserBefore;
  }

  /// @inheritdoc IStandardizedYieldAdapter
  /// @dev We don't check slippage here, assume that the slippage is checked by the caller.
  function convertToRedeem(address tokenOut, uint256 amountPivotTokenIn) external returns (uint256 amountOut) {
    console.log("convertToRedeem.0");
    address[] memory assetsForWithdraw = IMetaVault(PIVOT_TOKEN).assetsForWithdraw();
    require(tokenOut == assetsForWithdraw[0], IncorrectToken());

    uint maxWithdraw = IMetaVault(PIVOT_TOKEN).maxWithdraw(msg.sender);
    require(amountPivotTokenIn <= maxWithdraw, MaxWithdrawExceeded());

    uint balanceBefore = IERC20(tokenOut).balanceOf(msg.sender);
    IMetaVault(PIVOT_TOKEN).withdrawAssets(assetsForWithdraw, amountPivotTokenIn, new uint[](1));
    console.log("convertToRedeem.1");
    return IERC20(tokenOut).balanceOf(msg.sender) - balanceBefore;
  }

  function salvage(address token, address to, uint256 amount) external {
    require(msg.sender == owner, NotOwner());
    require(token != address(0), ZeroAddress());
    require(to != address(0), ZeroAddress());

    IERC20(token).safeTransfer(to, amount);
  }
  //endregion ---------------------------------- Write
}