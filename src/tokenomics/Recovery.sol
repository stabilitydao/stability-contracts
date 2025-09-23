// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {RecoveryLib} from "./libs/RecoveryLib.sol";
import {
ERC20Upgradeable,
IERC20,
IERC20Metadata
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Controllable, IControllable, IPlatform} from "../core/base/Controllable.sol";
import {ERC20BurnableUpgradeable} from
"@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
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

    //region ----------------------------------- View
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function recoveryPools() external view returns (address[] memory) {
        RecoveryLib.RecoveryStorage storage $ = RecoveryLib.getRecoveryTokenStorage();
        return $.recoveryPools.values();
    }


    //endregion ----------------------------------- View

    //region ----------------------------------- Restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function addRecoveryPools(address[] memory recoveryPools_) external onlyMultisig {
        RecoveryLib.addRecoveryPool(recoveryPools_);
    }

    function removeRecoveryPool(address pool_) external onlyMultisig {
        RecoveryLib.removeRecoveryPool(pool_);
    }

    function setThresholds(address[] memory tokens, uint[] memory thresholds) external onlyMultisig {
        RecoveryLib.setThresholds(tokens, thresholds);
    }
    //endregion ----------------------------------- Restricted actions

    //region ----------------------------------- Actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      Actions                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Transfer tokens on balance and send this function to process transferred amounts
    /// @custom:restrictions Anybody can call this function
    function registerTransferredAmounts(address[] memory tokens, uint[] memory amounts) external {
        RecoveryLib.registerTransferredAmounts(tokens, amounts, ISwapper(IPlatform(platform()).swapper()));
    }

    /// @notice Callback for Uniswap V3 swaps
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        return RecoveryLib.uniswapV3SwapCallback(amount0Delta, amount1Delta, data);
    }
    //endregion ----------------------------------- Actions


}
