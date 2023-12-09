// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title Simple ERC-1967 upgradeable proxy implementation
abstract contract UpgradeableProxy {
    error ImplementationIsNotContract();

    /// @dev This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
    bytes32 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev Emitted when the implementation is upgraded.
    event Upgraded(address indexed implementation);

    constructor() {
        assert(_IMPLEMENTATION_SLOT == bytes32(uint(keccak256("eip1967.proxy.implementation")) - 1));
    }

    /// @dev Post deploy initialisation for compatability with EIP-1167 factory
    function _init(address _logic) internal {
        // nosemgrep
        require(_implementation() == address(0), "Already inited");
        _setImplementation(_logic);
    }

    /// @dev Returns the current implementation address.
    function _implementation() internal view virtual returns (address impl) {
        bytes32 slot = _IMPLEMENTATION_SLOT;
        // solhint-disable-next-line no-inline-assembly
        //slither-disable-next-line assembly
        assembly {
            impl := sload(slot)
        }
    }

    /// @dev Upgrades the proxy to a new implementation.
    function _upgradeTo(address newImplementation) internal virtual {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /// @dev Stores a new address in the EIP1967 implementation slot.
    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) revert ImplementationIsNotContract();
        bytes32 slot = _IMPLEMENTATION_SLOT;
        // solhint-disable-next-line no-inline-assembly
        //slither-disable-next-line assembly
        assembly {
            sstore(slot, newImplementation)
        }
    }

    /**
     * @dev Delegates the current call to `implementation`.
     *
     * This function does not return to its internal call site, it will return directly to the external caller.
     */
    function _delegate(address implementation) internal virtual {
        //slither-disable-next-line assembly
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /**
     * @dev Delegates the current call to the address returned by `_implementation()`.
     *
     * This function does not return to its internal call site, it will return directly to the external caller.
     */
    function _fallback() internal virtual {
        _delegate(_implementation());
    }

    /// @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if no other
    /// function in the contract matches the call data.
    //slither-disable-next-line locked-ether
    fallback() external payable virtual {
        _fallback();
    }

    /// @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if call data
    /// is empty.
    //slither-disable-next-line locked-ether
    receive() external payable virtual {
        _fallback();
    }
}
