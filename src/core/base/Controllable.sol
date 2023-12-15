// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "../libs/SlotsLib.sol";
import "../../interfaces/IControllable.sol";
import "../../interfaces/IPlatform.sol";

/// @dev Base core contract.
///      It store an immutable platform proxy address in the storage and provides access control to inherited contracts.
/// @author Alien Deployer (https://github.com/a17)
/// @author 0xhokugava (https://github.com/0xhokugava)
abstract contract Controllable is Initializable, IControllable, ERC165 {
    using SlotsLib for bytes32;

    string public constant CONTROLLABLE_VERSION = "1.0.0";
    bytes32 internal constant _PLATFORM_SLOT = bytes32(uint(keccak256("eip1967.controllable.platform")) - 1);
    bytes32 internal constant _CREATED_BLOCK_SLOT = bytes32(uint(keccak256("eip1967.controllable.created_block")) - 1);

    /// @dev Prevent implementation init
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize contract after setup it as proxy implementation
    ///         Save block.timestamp in the "created" variable
    /// @dev Use it only once after first logic setup
    /// @param platform_ Platform address
    //slither-disable-next-line naming-convention
    function __Controllable_init(address platform_) internal onlyInitializing {
        if (platform_ == address(0) || IPlatform(platform_).multisig() == address(0)) {
            revert IncorrectZeroArgument();
        }
        SlotsLib.set(_PLATFORM_SLOT, platform_); // syntax for forge coverage
        _CREATED_BLOCK_SLOT.set(block.number);
        emit ContractInitialized(platform_, block.timestamp, block.number);
    }

    modifier onlyGovernance() {
        _requireGovernance();
        _;
    }

    modifier onlyMultisig() {
        _requireMultisig();
        _;
    }

    modifier onlyGovernanceOrMultisig() {
        _requireGovernanceOrMultisig();
        _;
    }

    modifier onlyOperator() {
        _requireOperator();
        _;
    }

    modifier onlyFactory() {
        _requireFactory();
        _;
    }

    // ************* SETTERS/GETTERS *******************

    /// @inheritdoc IControllable
    function platform() public view override returns (address) {
        return _PLATFORM_SLOT.getAddress();
    }

    /// @inheritdoc IControllable
    function createdBlock() external view override returns (uint) {
        return _CREATED_BLOCK_SLOT.getUint();
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IControllable).interfaceId || super.supportsInterface(interfaceId);
    }

    function _requireGovernance() internal view {
        if (IPlatform(platform()).governance() != msg.sender) {
            revert NotGovernance();
        }
    }

    function _requireMultisig() internal view {
        if (!IPlatform(platform()).isOperator(msg.sender)) {
            revert NotMultisig();
        }
    }

    function _requireGovernanceOrMultisig() internal view {
        IPlatform _platform = IPlatform(platform());
        // nosemgrep
        if (_platform.governance() != msg.sender && _platform.multisig() != msg.sender) {
            revert NotGovernanceAndNotMultisig();
        }
    }

    function _requireOperator() internal view {
        if (!IPlatform(platform()).isOperator(msg.sender)) {
            revert NotOperator();
        }
    }

    function _requireFactory() internal view {
        if (IPlatform(platform()).factory() != msg.sender) {
            revert NotFactory();
        }
    }
}
