// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Controllable, IControllable, IERC165} from "../core/base/Controllable.sol";
import {IMetaVaultAmmAdapter} from "../interfaces/IMetaVaultAmmAdapter.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {AmmAdapterIdLib} from "./libs/AmmAdapterIdLib.sol";
import {ConstantsLib} from "../core/libs/ConstantsLib.sol";
import {IMetaVault} from "../interfaces/IMetaVault.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";

/// @title AMM adapter for Meta Vaults
/// @dev It's not suitable for MultiVaults, see i.e. poolTokens implementation.
/// Changelog:
///   1.0.2: add empty IAmmAdapter.getTwaPrice
///   1.0.1: fix incorrect calculation of minSharesOut in swap()
///   1.0.0: Initial version
/// @author dvpublic (https://github.com/dvpublic)
contract MetaVaultAdapter is Controllable, IMetaVaultAmmAdapter {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.2";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error IncorrectTokens();
    error IncorrectAmountConsumed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function init(address platform_) external initializer {
        __Controllable_init(platform_);
    }

    //region ------------------------------------ User actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    //slither-disable-next-line reentrancy-events
    function swap(
        address pool,
        address tokenIn,
        address tokenOut,
        address recipient,
        uint priceImpactTolerance
    ) external {
        IMetaVault metaVault = IMetaVault(pool);

        uint amount = IERC20(tokenIn).balanceOf(address(this));
        // slither-disable-next-line uninitialized-state
        uint amountOut;

        if (tokenIn == pool) {
            // swap Meta Vault to asset
            uint balance = metaVault.balanceOf(address(this));

            address[] memory assets = metaVault.assetsForWithdraw();
            require(assets.length == 1 && assets[0] == tokenOut, IncorrectTokens());

            // calculate min asset amounts out
            uint[] memory minAssetAmountsOut = new uint[](1);
            minAssetAmountsOut[0] = getPrice(pool, tokenIn, tokenOut, amount)
                * (ConstantsLib.DENOMINATOR - priceImpactTolerance) / ConstantsLib.DENOMINATOR;

            // slither-disable-next-line unused-return
            metaVault.withdrawAssets(assets, balance, minAssetAmountsOut);

            amountOut = IERC20(assets[0]).balanceOf(address(this));
            IERC20(assets[0]).safeTransfer(recipient, amountOut);
        } else if (tokenOut == pool) {
            // swap asset to Meta Vault
            address[] memory assets = metaVault.assetsForDeposit();
            require(assets.length == 1 && assets[0] == tokenIn, IncorrectTokens());
            uint[] memory amountsMax = new uint[](1);
            amountsMax[0] = amount;

            (
                , // consumed amounts
                , // amount meta vault tokens
                uint valueOut // amount of meta vault shares to be received
            ) = metaVault.previewDepositAssets(assets, amountsMax);

            IERC20(tokenIn).forceApprove(pool, amount);
            uint balanceBefore = metaVault.balanceOf(recipient);
            metaVault.depositAssets(
                assets,
                amountsMax,
                valueOut * (ConstantsLib.DENOMINATOR - priceImpactTolerance) / ConstantsLib.DENOMINATOR,
                recipient
            );

            amountOut = metaVault.balanceOf(recipient) - balanceBefore;

            // ensure that all input tokens were deposited
            require(IERC20(tokenIn).balanceOf(address(this)) == 0, IncorrectAmountConsumed());
        } else {
            revert IncorrectTokens();
        }

        emit SwapInPool(pool, tokenIn, tokenOut, recipient, priceImpactTolerance, amount, amountOut);
    }

    //endregion ---------------------------------- User actions

    //region ------------------------------------ View functions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function ammAdapterId() external pure returns (string memory) {
        return AmmAdapterIdLib.META_VAULT;
    }

    /// @inheritdoc IAmmAdapter
    function poolTokens(address pool) public view returns (address[] memory tokens) {
        address[] memory vaults = IMetaVault(pool).vaults();
        tokens = new address[](1 + vaults.length);

        // wrapped meta vault itself is the first token
        tokens[0] = pool;

        // peg assets of all embedded meta-vaults
        // the tokens must have the same order as vaults in the meta-vault, see {getPrice} implementation
        for (uint i = 0; i < vaults.length; i++) {
            tokens[i + 1] = IMetaVault(vaults[i]).pegAsset();
        }
    }

    /// @inheritdoc IAmmAdapter
    function getLiquidityForAmounts(address, uint[] memory) external pure returns (uint, uint[] memory) {
        revert("Not supported");
    }

    /// @inheritdoc IAmmAdapter
    function getProportions(address) external pure returns (uint[] memory) {
        revert("Not supported");
    }

    /// @inheritdoc IAmmAdapter
    function getPrice(address pool, address tokenIn, address tokenOut, uint amount) public view returns (uint) {
        uint tokenInDecimals = IERC20Metadata(tokenIn).decimals();
        uint tokenOutDecimals = IERC20Metadata(tokenOut).decimals();

        // For zero value provided amount 1.0 (10 ** decimals of tokenIn) will be used.
        // slither-disable-next-line incorrect-equality
        if (amount == 0) {
            amount = 10 ** tokenInDecimals;
        }

        // get price of MetaVault in USD
        // slither-disable-next-line unused-return
        (uint priceMetaVault,) = IMetaVault(pool).price();

        if (tokenIn == pool) {
            // get price of tokenOut in USD
            // slither-disable-next-line unused-return
            (uint priceTokenOut,) = IPriceReader(IPlatform(platform()).priceReader()).getPrice(tokenOut);

            // MetaVault to asset
            return amount * (10 ** tokenOutDecimals) * priceMetaVault / priceTokenOut / (10 ** tokenInDecimals);
        } else if (tokenOut == pool) {
            // slither-disable-next-line unused-return
            (uint priceTokenIn,) = IPriceReader(IPlatform(platform()).priceReader()).getPrice(tokenIn);

            // Asset to MetaVault
            return amount * (10 ** tokenOutDecimals) * priceTokenIn / priceMetaVault / (10 ** tokenInDecimals);
        }

        revert IncorrectTokens();
    }

    /// @inheritdoc IAmmAdapter
    function getTwaPrice(address /*pool*/, address /*tokenIn*/, address /*tokenOut*/, uint /*amount*/, uint32 /*period*/) external pure returns (uint) {
        revert("Not supported");
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(Controllable, IERC165) returns (bool) {
        return interfaceId == type(IAmmAdapter).interfaceId || interfaceId == type(IMetaVaultAmmAdapter).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //endregion -------------------------------- View functions

    //region -------------------------------- IMetaVaultAmmAdapter
    /// @inheritdoc IMetaVaultAmmAdapter
    function assetForDeposit(address pool) external view returns (address) {
        // we assume here that MetaUSD doesn't support multiple assets for deposit
        return IMetaVault(pool).assetsForDeposit()[0];
    }

    /// @inheritdoc IMetaVaultAmmAdapter
    function assetForWithdraw(address pool) external view returns (address) {
        // we assume here that MetaUSD doesn't support multiple assets for withdraw
        return IMetaVault(pool).assetsForWithdraw()[0];
    }
    //endregion ------------------------------- IMetaVaultAmmAdapter
}
