// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title Minimal library for setting / getting slot variables (used in upgradable proxy contracts)
library SlotsLib {
    /// @dev Gets a slot as an address
    function getAddress(bytes32 slot) internal view returns (address result) {
        assembly {
            result := sload(slot)
        }
    }

    /// @dev Gets a slot as uint256
    function getUint(bytes32 slot) internal view returns (uint result) {
        assembly {
            result := sload(slot)
        }
    }

    /// @dev Sets a slot with address
    /// @notice Check address for 0 at the setter
    function set(bytes32 slot, address value) internal {
        assembly {
            sstore(slot, value)
        }
    }

    /// @dev Sets a slot with uint
    function set(bytes32 slot, uint value) internal {
        assembly {
            sstore(slot, value)
        }
    }
}
