// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {RecoveryRelayerLib} from "./libs/RecoveryRelayerLib.sol";
import {Controllable, IControllable, IPlatform} from "../core/base/Controllable.sol";
import {IRecoveryRelayer, IRecoveryBase} from "../interfaces/IRecoveryRelayer.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// import {ISwapper} from "../interfaces/ISwapper.sol";
// import {IPriceReader} from "../interfaces/IPriceReader.sol";

/// @title Contract to collect recovery amounts on not-main chains and transfer them to the main chain
/// @author omriss (https://github.com/omriss)
contract RecoveryRelayer is Controllable, IRecoveryRelayer {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRecoveryBase
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

    /// @inheritdoc IRecoveryRelayer
    function threshold(address token) external view override returns (uint) {
        RecoveryRelayerLib.RecoveryRelayerStorage storage $ = RecoveryRelayerLib.getRecoveryRelayerStorage();
        return $.tokenThresholds[token];
    }

    /// @inheritdoc IRecoveryRelayer
    function whitelisted(address operator_) public view override returns (bool) {
        if (IPlatform(platform()).multisig() == operator_) {
            return true;
        }

        RecoveryRelayerLib.RecoveryRelayerStorage storage $ = RecoveryRelayerLib.getRecoveryRelayerStorage();
        return $.whitelistOperators[operator_];
    }

    /// @inheritdoc IRecoveryRelayer
    function isTokenRegistered(address token) external view override returns (bool) {
        RecoveryRelayerLib.RecoveryRelayerStorage storage $ = RecoveryRelayerLib.getRecoveryRelayerStorage();
        return $.registeredTokens.contains(token);
    }

    /// @inheritdoc IRecoveryRelayer
    function getListTokensToSwap() external view returns (address[] memory tokens) {
        RecoveryRelayerLib.RecoveryRelayerStorage storage $ = RecoveryRelayerLib.getRecoveryRelayerStorage();
        return RecoveryRelayerLib.getListTokensToSwap($);
    }

    /// @inheritdoc IRecoveryRelayer
    function getListRegisteredTokens() external view returns (address[] memory tokens) {
        RecoveryRelayerLib.RecoveryRelayerStorage storage $ = RecoveryRelayerLib.getRecoveryRelayerStorage();
        return RecoveryRelayerLib.getListRegisteredTokens($);
    }

    //endregion ----------------------------------- View

    //region ----------------------------------- Restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRecoveryRelayer
    function setThresholds(address[] memory tokens, uint[] memory thresholds) external onlyOperator {
        RecoveryRelayerLib.setThresholds(tokens, thresholds);
    }

    /// @inheritdoc IRecoveryRelayer
    function changeWhitelist(address operator_, bool add_) external onlyOperator {
        RecoveryRelayerLib.changeWhitelist(operator_, add_);
    }

    //endregion ----------------------------------- Restricted actions

    //region ----------------------------------- Actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      Actions                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRecoveryBase
    function registerAssets(address[] memory tokens) external override onlyWhitelisted {
        RecoveryRelayerLib.registerAssets(tokens);
    }

    //endregion ----------------------------------- Actions

    function _onlyWhitelisted() internal view {
        require(whitelisted(msg.sender), RecoveryRelayerLib.NotWhitelisted());
    }
}
