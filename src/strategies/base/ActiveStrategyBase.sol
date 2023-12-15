// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./StrategyBase.sol";
import "../../interfaces/IActiveStrategy.sol";

abstract contract ActiveStrategyBase is StrategyBase, IActiveStrategy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of FarmingStrategyBase implementation
    string public constant VERSION_ACTIVE_STRATEGY_BASE = "0.1.0";

    /// @inheritdoc IActiveStrategy
    function rebalanceWithSwap(
        address[] memory,
        address[] memory,
        uint[] memory,
        bytes[] memory,
        address
    ) external virtual {
        revert NotSupported();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(StrategyBase) returns (bool) {
        return interfaceId == type(IActiveStrategy).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IActiveStrategy
    function needRebalance() external view returns (bool) {
        return _needRebalance();
    }

    /// @inheritdoc IActiveStrategy
    function needRebalanceWithSwap()
        external
        view
        virtual
        returns (bool, address[] memory, address[] memory, uint[] memory)
    {
        revert NotSupported();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIRTUAL LOGIC                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _needRebalance() internal view virtual returns (bool);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     OVERRIDEN LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _beforeDeposit() internal virtual override {
        if (_needRebalance()) {
            revert NeedRebalance();
        }
    }

    /// @inheritdoc StrategyBase
    function _beforeWithdraw() internal virtual override {
        if (_needRebalance()) {
            revert NeedRebalance();
        }
    }

    /// @inheritdoc StrategyBase
    function _beforeDoHardWork() internal virtual override {
        if (_needRebalance()) {
            revert NeedRebalance();
        }
    }
}
