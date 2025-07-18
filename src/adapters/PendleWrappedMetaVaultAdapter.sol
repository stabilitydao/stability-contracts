// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
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
    //slither-disable-next-line naming-convention
    address public immutable PIVOT_TOKEN;
    address public immutable owner;

    /// @notice Only whitelisted addresses are allowed to disable last-block defence. SY must be whitelisted.
    mapping(address => bool) public whitelisted;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         ERRORS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    error NotOwner();
    error ZeroAddress();
    error IncorrectToken();
    error MaxWithdrawExceeded();
    error NotWhitelisted();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         Initialization                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    constructor(address metaVault_) {
        require(metaVault_ != address(0), ZeroAddress());
        PIVOT_TOKEN = metaVault_;
        owner = msg.sender;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Restricted actions                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice SY must be whitelisted to be able to disable last-block defence
    function changeWhitelist(address account, bool whitelisted_) external {
        require(msg.sender == owner, NotOwner());
        require(account != address(0), ZeroAddress());

        whitelisted[account] = whitelisted_;
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
    function previewConvertToDeposit(address tokenIn, uint amountTokenIn) external view returns (uint amountOut) {
        //------------------- ensure that the tokenIn is the asset of the meta vault
        address[] memory assetsForDeposit = IMetaVault(PIVOT_TOKEN).assetsForDeposit();
        require(tokenIn == assetsForDeposit[0], IncorrectToken());

        //------------------- convert asset amount to the amount of meta vault tokens that will be minted on deposit
        uint[] memory amountsMax = new uint[](1);
        amountsMax[0] = amountTokenIn;

        // slither-disable-next-line unused-return
        (, amountOut,) = IMetaVault(PIVOT_TOKEN).previewDepositAssets(assetsForDeposit, amountsMax);
    }

    /// @inheritdoc IStandardizedYieldAdapter
    function previewConvertToRedeem(address tokenOut, uint amountPivotTokenIn) external view returns (uint amountOut) {
        //------------------- ensure that the tokenOut is the asset of the meta vault
        address[] memory assetsForWithdraw = IMetaVault(PIVOT_TOKEN).assetsForWithdraw();
        require(tokenOut == assetsForWithdraw[0], IncorrectToken());

        //------------------- convert meta vault balance => USD amount => asset amount
        // slither-disable-next-line unused-return
        (uint priceMetaVaultToken,) = IMetaVault(PIVOT_TOKEN).price();
        IPriceReader priceReader = IPriceReader(IPlatform(IControllable(PIVOT_TOKEN).platform()).priceReader());
        // slither-disable-next-line unused-return
        (uint priceAsset,) = priceReader.getPrice(tokenOut);

        amountOut = Math.mulDiv(amountPivotTokenIn, priceMetaVaultToken, priceAsset, Math.Rounding.Ceil)
            * 10 ** IERC20Metadata(tokenOut).decimals() / 1e18;
    }
    //endregion ---------------------------------- View

    //region ---------------------------------- Write
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         Write                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStandardizedYieldAdapter
    /// @dev We don't check slippage here, assume that the slippage is checked by the caller.
    function convertToDeposit(address tokenIn, uint amountTokenIn) external returns (uint amountOut) {
        address[] memory assetsForDeposit = IMetaVault(PIVOT_TOKEN).assetsForDeposit();
        require(tokenIn == assetsForDeposit[0], IncorrectToken());

        // only whitelisted addresses can disable last-block defence
        require(whitelisted[msg.sender], NotWhitelisted());

        // for simplicity we don't take into account maxDeposit (otherwise we need new SY)
        // maxDeposit is unlimited for metaUSD and metaS

        uint[] memory amountsMax = new uint[](1);
        amountsMax[0] = amountTokenIn;

        IERC20(assetsForDeposit[0]).forceApprove(PIVOT_TOKEN, amountsMax[0]);

        uint balanceUserBefore = IMetaVault(PIVOT_TOKEN).balanceOf(msg.sender);

        IMetaVault(PIVOT_TOKEN).setLastBlockDefenseDisabledTx(
            uint(IMetaVault.LastBlockDefenseDisableMode.DISABLE_TX_DONT_UPDATE_MAPS_2)
        );
        IMetaVault(PIVOT_TOKEN).depositAssets(assetsForDeposit, amountsMax, 0, msg.sender);
        IMetaVault(PIVOT_TOKEN).setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0));

        amountOut = IMetaVault(PIVOT_TOKEN).balanceOf(msg.sender) - balanceUserBefore;
    }

    /// @inheritdoc IStandardizedYieldAdapter
    /// @dev We don't check slippage here, assume that the slippage is checked by the caller.
    function convertToRedeem(address tokenOut, uint amountPivotTokenIn) external returns (uint amountOut) {
        address[] memory assetsForWithdraw = IMetaVault(PIVOT_TOKEN).assetsForWithdraw();
        require(tokenOut == assetsForWithdraw[0], IncorrectToken());

        // only whitelisted addresses can disable last-block defence
        require(whitelisted[msg.sender], NotWhitelisted());

        // metavalut balance is dynamic and can vary on the level of dust
        amountPivotTokenIn = Math.min(IMetaVault(PIVOT_TOKEN).balanceOf(address(this)), amountPivotTokenIn);

        uint maxWithdraw = IMetaVault(PIVOT_TOKEN).maxWithdraw(address(this));
        require(amountPivotTokenIn <= maxWithdraw, MaxWithdrawExceeded());

        uint balanceBefore = IERC20(tokenOut).balanceOf(address(this));
        IMetaVault(PIVOT_TOKEN).setLastBlockDefenseDisabledTx(
            uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1)
        );
        // slither-disable-next-line unused-return
        IMetaVault(PIVOT_TOKEN).withdrawAssets(assetsForWithdraw, amountPivotTokenIn, new uint[](1));
        IMetaVault(PIVOT_TOKEN).setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.ENABLED_0));

        uint withdrawn = IERC20(tokenOut).balanceOf(address(this)) - balanceBefore;
        IERC20(tokenOut).safeTransfer(msg.sender, withdrawn);

        return withdrawn;
    }

    function salvage(address token, address to, uint amount) external {
        require(msg.sender == owner, NotOwner());
        require(token != address(0), ZeroAddress());
        require(to != address(0), ZeroAddress());

        IERC20(token).safeTransfer(to, amount);
    }
    //endregion ---------------------------------- Write
}
