// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../interfaces/IChildTokenFactory.sol";

/// @notice ChildTokenFactory
/// @author Jude (https://github.com/iammrjude)
contract ChildTokenFactory is IChildTokenFactory {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.ChildTokenFactory")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant CHILDTOKENFACTORY_STORAGE_LOCATION = 0x60d85ab01da9561f1b5ee0277c3493def657ac9ed7765078710b0dc83f201c00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.ChildTokenFactory
    struct ChildTokenFactoryStorage {
        address parent;
    }
    
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IChildTokenFactory
    function deployChildERC20(
        address parentToken,
        uint64 parentChainId,
        string memory name,
        string memory symbol
    ) external returns(address) {}

    /// @inheritdoc IChildTokenFactory
    function deployChildERC721(
        address parentToken,
        uint64 parentChainId,
        string memory name,
        string memory symbol,
        string memory baseURI
    ) external returns(address) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getStorage() private pure returns (ChildTokenFactoryStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := CHILDTOKENFACTORY_STORAGE_LOCATION
        }
    }
}