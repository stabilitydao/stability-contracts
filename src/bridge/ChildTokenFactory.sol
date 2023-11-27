// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../core/base/Controllable.sol";
import "../interfaces/IChildTokenFactory.sol";
import "./ChildERC20.sol";
import "./ChildERC721.sol";

/// @notice ChildTokenFactory
/// @author Jude (https://github.com/iammrjude)
contract ChildTokenFactory is Controllable, IChildTokenFactory {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = '1.0.0';

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
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(address platform_) external initializer {
        __Controllable_init(platform_);
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
    ) external returns(address) {
        ChildERC20 childERC20 = new ChildERC20(parentToken, parentChainId, name, symbol);
        return address(childERC20);
    }

    /// @inheritdoc IChildTokenFactory
    function deployChildERC721(
        address parentToken,
        uint64 parentChainId,
        string memory name,
        string memory symbol,
        string memory baseURI
    ) external returns(address) {
        ChildERC721 childERC721 = new ChildERC721(parentToken, parentChainId, name, symbol, baseURI);
        return address(childERC721);
    }

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