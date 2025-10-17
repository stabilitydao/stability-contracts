// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {RecoveryLib} from "./libs/RecoveryLib.sol";
import {Controllable, IControllable, IPlatform} from "../core/base/Controllable.sol";
import {IRecovery} from "../interfaces/IRecovery.sol";
import {IUniswapV3SwapCallback} from "../integrations/uniswapv3/IUniswapV3SwapCallback.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";

/// @title Recovery contract to swap assets on recovery tokens in recovery pools
/// @author dvpublic (https://github.com/dvpublic)
/// Changelog:
contract Recovery is Controllable, IRecovery, IUniswapV3SwapCallback {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRecovery
    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
    }

    modifier onlyWhitelisted() {
        require(whitelisted(msg.sender), RecoveryLib.NotWhitelisted());
        _;
    }

    //region ----------------------------------- View
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRecovery
    function recoveryPools() external view returns (address[] memory) {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        return $.recoveryPools.values();
    }

    /// @inheritdoc IRecovery
    function threshold(address token) external view returns (uint) {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        return $.tokenThresholds[token];
    }

    /// @inheritdoc IRecovery
    function whitelisted(address operator_) public view returns (bool) {
        if (IPlatform(platform()).multisig() == operator_) {
            return true;
        }

        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        return $.whitelistOperators[operator_];
    }

    /// @inheritdoc IRecovery
    function isTokenRegistered(address token) external view returns (bool) {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        return $.registeredTokens.contains(token);
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
    function setThresholds(address[] memory tokens, uint[] memory thresholds) external onlyMultisig {
        RecoveryLib.setThresholds(tokens, thresholds);
    }

    /// @inheritdoc IRecovery
    function changeWhitelist(address operator_, bool add_) external onlyMultisig {
        RecoveryLib.changeWhitelist(operator_, add_);
    }

    //endregion ----------------------------------- Restricted actions

    //region ----------------------------------- Actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      Actions                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRecovery
    function registerAssets(address[] memory tokens) external onlyWhitelisted {
        RecoveryLib.registerAssets(tokens);
    }

    /// @inheritdoc IRecovery
    function swapAssetsToRecoveryTokens(uint indexFirstRecoveryPool1) external onlyWhitelisted {
        RecoveryLib.swapAssetsToRecoveryTokens(indexFirstRecoveryPool1, ISwapper(IPlatform(platform()).swapper()));
    }

    /// @notice Callback for Uniswap V3 swaps
    function uniswapV3SwapCallback(int amount0Delta, int amount1Delta, bytes calldata data) external override {
        return RecoveryLib.uniswapV3SwapCallback(amount0Delta, amount1Delta, data);
    }
    //endregion ----------------------------------- Actions
}
