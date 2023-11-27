// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../core/base/Controllable.sol";
import "../interfaces/IBridge.sol";

/// @title Stability Bridge
/// @author Jude (https://github.com/iammrjude)
contract Bridge is Controllable, IBridge {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = '1.0.0';

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.Bridge")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant BRIDGE_STORAGE_LOCATION = 0x052cfeb6b58cb7c758df4b774795a7771143349338d88867c9a9d655662bfd00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.Bridge
    struct BridgeStorage {
        mapping (bytes32 linkHash => Link) link;
        Link[] links;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    function initialize(address platform_) external initializer {
        __Controllable_init(platform_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBridge
    function chainId() external view returns(uint64) {
        return uint64(block.chainid);
    }

    /// @inheritdoc IBridge
    function link(bytes32 linkHash) external view returns(Link memory) {
        return _getStorage().link[linkHash];
    }

    /// @inheritdoc IBridge
    function links() external view returns (Link[] memory) {
        return _getStorage().links;
    }

    /// @inheritdoc IBridge
    function adapterStatus(string memory adapterId) external view returns(bool active, uint priority) {}

    /// @inheritdoc IBridge
    function adapters() external view returns(string[] memory) {}

    /// @inheritdoc IBridge
    function getTarget(address token, uint64 chainTo) external view returns(address targetToken, bytes32 linkHash) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBridge
    function interChainTransfer(address token, uint amountOrTokenId, uint64 chainTo) external payable {}

    /// @inheritdoc IBridge
    function interChainReceive(address token, uint amountOrTokenId, uint64 chainFrom) external {}

    /// @inheritdoc IBridge
    function addLink(Link memory link_) external onlyOperator {
        _getStorage().links.push(link_);
    }

    /// @inheritdoc IBridge
    function setLinkAdapters(string[] memory adapterIds) external onlyOperator {}

    function setTarget(address token, uint64 chainTo, address targetToken, bytes32 linkHash) external {}

    function addAdapters(string[] memory adapterIds, uint priority) external {}

    /// @inheritdoc IBridge
    function changeAdapterPriority(string memory adapterId, uint newPriority) external onlyOperator {}

    /// @inheritdoc IBridge
    function emergencyStopAdapter(string memory adapterId, string memory reason) external onlyOperator {}

    /// @inheritdoc IBridge
    function enableAdapter(string memory adapterId) external {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getStorage() private pure returns (BridgeStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := BRIDGE_STORAGE_LOCATION
        }
    }
}