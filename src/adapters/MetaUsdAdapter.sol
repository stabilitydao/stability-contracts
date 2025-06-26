// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Controllable, IControllable, IERC165} from "../core/base/Controllable.sol";
import {IMetaUsdAmmAdapter} from "../interfaces/IMetaUsdAmmAdapter.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {AmmAdapterIdLib} from "./libs/AmmAdapterIdLib.sol";
import {ConstantsLib} from "../core/libs/ConstantsLib.sol";
import {IMetaVault} from "../interfaces/IMetaVault.sol";

/// @title AMM adapter for Wrapped Meta USD
/// Changelog:
///   1.0.0: Initial version
/// @author dvpublic (https://github.com/dvpublic)
contract MetaUsdAdapter is Controllable, IMetaUsdAmmAdapter {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

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
        console.log("MetaUsdAdapter.swap");
        IMetaVault metaVault = IMetaVault(pool);

        uint amount = IERC20(tokenIn).balanceOf(address(this));
        uint amountOut;

        if (tokenIn == pool) {
            // swap Meta USD to asset
            uint balance = metaVault.balanceOf(address(this)); // todo

            address[] memory assets = metaVault.assetsForWithdraw();
            require(assets.length == 1 && assets[0] == tokenOut, IncorrectTokens());

            uint[] memory minAssetAmountsOut = new uint[](1);
            minAssetAmountsOut[0] = amount
                * (ConstantsLib.DENOMINATOR - priceImpactTolerance) / ConstantsLib.DENOMINATOR;

            metaVault.withdrawAssets(assets, balance, minAssetAmountsOut);

            amountOut = IERC20(assets[0]).balanceOf(address(this));
            IERC20(assets[0]).transfer(recipient, amountOut);
        } else if (tokenOut == pool) {
            // swap asset to Meta USD
            address[] memory assets = metaVault.assetsForDeposit();
            require(assets.length == 1 && assets[0] == tokenOut, IncorrectTokens());
            uint[] memory amountsMax = new uint[](1);
            amountsMax[0] = amount;

            (uint[] memory amountsConsumed, uint sharesOut,) = metaVault.previewDepositAssets(assets, amountsMax);
            // todo Do we need to refund the excess instead of reverting?
            require(amountsConsumed.length == 1 && amountsConsumed[0] == amount, IncorrectAmountConsumed());

            metaVault.depositAssets(
                assets,
                amountsMax,
                sharesOut * (ConstantsLib.DENOMINATOR - priceImpactTolerance) / ConstantsLib.DENOMINATOR,
                address(this)
            );

            amountOut = metaVault.balanceOf(address(this)); // todo
            metaVault.transfer(recipient, amountOut);
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
        return AmmAdapterIdLib.META_USD;
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
        console.log("MetaUsdAdapter.getPrice");
        address[] memory vaults = IMetaVault(pool).vaults();
        address[] memory tokens = poolTokens(pool);

        // we assume here that all tokens are in the same order as vaults, see {poolTokens} implementation

        if (tokenIn == tokens[0]) {
            // Meta USD to asset
            for (uint i = 1; i < tokens.length; i++) {
                if (tokenOut == tokens[i]) {
                    (uint price, ) = IMetaVault(vaults[i - 1]).price();
                    // todo should we check if the price is trusted here?
                    return price * amount / 1e18;
                }
            }
        } else if (tokenOut == tokens[0]) {
            // Asset to Meta USD
            for (uint i = 1; i < tokens.length; i++) {
                if (tokenIn == tokens[i]) {
                    (uint price, ) = IMetaVault(vaults[i - 1]).price();
                    // todo should we check if the price is trusted here?
                    return amount * 1e18 / price;
                }
            }
        }

        revert IncorrectTokens();
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(Controllable, IERC165) returns (bool) {
        return
            interfaceId == type(IAmmAdapter).interfaceId
            || interfaceId == type(IMetaUsdAmmAdapter).interfaceId
            || super.supportsInterface(interfaceId);
    }
    //endregion -------------------------------- View functions

    //region -------------------------------- IMetaUsdAmmAdapter
    /// @inheritdoc IMetaUsdAmmAdapter
    function assetForDeposit(address pool) external view returns (address) {
        // we assume here that MetaUSD doesn't support multiple assets for deposit
        return IMetaVault(pool).assetsForDeposit()[0];
    }

    /// @inheritdoc IMetaUsdAmmAdapter
    function assetForWithdraw(address pool) external view returns (address) {
        // we assume here that MetaUSD doesn't support multiple assets for withdraw
        return IMetaVault(pool).assetsForWithdraw()[0];
    }
    //endregion ------------------------------- IMetaUsdAmmAdapter
}
