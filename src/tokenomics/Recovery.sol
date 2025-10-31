// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {RecoveryLib} from "./libs/RecoveryLib.sol";
import {Controllable, IControllable, IPlatform} from "../core/base/Controllable.sol";
import {IRecovery} from "../interfaces/IRecovery.sol";
import {IUniswapV3SwapCallback} from "../integrations/uniswapv3/IUniswapV3SwapCallback.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";

/// @title Recovery contract to swap assets on recovery tokens in recovery pools
/// @author dvpublic (https://github.com/dvpublic)
/// Changelog:
///   1.2.1: replace event SwapAssets by event SwapAssets2
///   1.2.0: getListTokensToSwap excludes meta vault tokens, add getListRegisteredTokens, fix getPoolWithMinPrice logic
///          Use onlyOperator restrictions for setThresholds and changeWhitelist
///          Add possibility to forward bought recovery tokens instead of burning
///   1.1.0: Add getListTokensToSwap, swapAssets, fillRecoveryPools, remove swapAssetsToRecoveryTokens
contract Recovery is Controllable, IRecovery, IUniswapV3SwapCallback {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.2.1";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRecovery
    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
    }

    modifier onlyWhitelisted() {
        _onlyWhitelisted();
        _;
    }

    //region ----------------------------------- View
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRecovery
    function recoveryPools() external view override returns (address[] memory) {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        return $.recoveryPools.values();
    }

    /// @inheritdoc IRecovery
    function threshold(address token) external view override returns (uint) {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        return $.tokenThresholds[token];
    }

    /// @inheritdoc IRecovery
    function whitelisted(address operator_) public view override returns (bool) {
        if (IPlatform(platform()).multisig() == operator_) {
            return true;
        }

        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        return $.whitelistOperators[operator_];
    }

    /// @inheritdoc IRecovery
    function isTokenRegistered(address token) external view override returns (bool) {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        return $.registeredTokens.contains(token);
    }

    /// @inheritdoc IRecovery
    function getListTokensToSwap() external view returns (address[] memory tokens) {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        return RecoveryLib.getListTokensToSwap($);
    }

    /// @inheritdoc IRecovery
    function getListRegisteredTokens() external view returns (address[] memory tokens) {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        return RecoveryLib.getListRegisteredTokens($);
    }

    /// @notice Return receiver of the bought recovery tokens. 0 - tokens are burnt
    function getReceiver(address recoveryToken_) external view returns (address receiver) {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        return $.receivers[recoveryToken_];
    }

    //endregion ----------------------------------- View

    //region ----------------------------------- Restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRecovery
    function addRecoveryPools(address[] memory recoveryPools_) external onlyMultisig {
        RecoveryLib.addRecoveryPool(recoveryPools_);
    }

    /// @inheritdoc IRecovery
    function removeRecoveryPool(address pool_) external onlyMultisig {
        RecoveryLib.removeRecoveryPool(pool_);
    }

    /// @inheritdoc IRecovery
    function setThresholds(address[] memory tokens, uint[] memory thresholds) external onlyOperator {
        RecoveryLib.setThresholds(tokens, thresholds);
    }

    /// @inheritdoc IRecovery
    function changeWhitelist(address operator_, bool add_) external onlyOperator {
        RecoveryLib.changeWhitelist(operator_, add_);
    }

    function setReceiver(address recoveryToken_, address receiver_) external onlyOperator {
        RecoveryLib.setReceiver(recoveryToken_, receiver_);
    }

    //endregion ----------------------------------- Restricted actions

    //region ----------------------------------- Actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      Actions                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRecovery
    function registerAssets(address[] memory tokens) external override onlyWhitelisted {
        RecoveryLib.registerAssets(tokens);
    }

    /// @inheritdoc IRecovery
    function swapAssets(address[] memory tokens, uint indexRecoveryPool1) external override onlyWhitelisted {
        IPlatform platform_ = IPlatform(platform());
        RecoveryLib.swapAssets(
            ISwapper(platform_.swapper()), IPriceReader(platform_.priceReader()), tokens, indexRecoveryPool1
        );
    }

    /// @inheritdoc IRecovery
    function fillRecoveryPools(
        address metaVaultToken_,
        uint indexFirstRecoveryPool1,
        uint maxCountPoolsToSwap_
    ) external override onlyWhitelisted {
        RecoveryLib.fillRecoveryPools(metaVaultToken_, indexFirstRecoveryPool1, maxCountPoolsToSwap_);
    }

    /// @notice Callback for Uniswap V3 swaps
    function uniswapV3SwapCallback(int amount0Delta, int amount1Delta, bytes calldata data) external override {
        return RecoveryLib.uniswapV3SwapCallback(amount0Delta, amount1Delta, data);
    }
    //endregion ----------------------------------- Actions

    function _onlyWhitelisted() internal view {
        require(whitelisted(msg.sender), RecoveryLib.NotWhitelisted());
    }
}
