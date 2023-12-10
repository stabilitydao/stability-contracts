// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../interfaces/IChildERC721.sol";

/// @notice ChildERC721
/// @author Jude (https://github.com/iammrjude)
contract ChildERC721 is ERC721, IChildERC721 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.ChildERC721")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant CHILDERC721_STORAGE_LOCATION = 0xbb2be940d8cc9a19c405bb2e9a1cc56dc19be950653b2045384a2537f8e3f800;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.ChildERC721
    struct ChildERC721Storage {
        address parentToken;
        uint16 parentChainId;
        string baseURI;
        address bridge;
    }
    
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(
        address parentToken,
        uint16 parentChainId,
        string memory name,
        string memory symbol,
        string memory baseURI,
        address bridge_
    ) ERC721(name, symbol) payable {
        ChildERC721Storage storage $ = _getStorage();
        $.parentToken = parentToken;
        $.parentChainId = parentChainId;
        $.baseURI = baseURI;
        $.bridge = bridge_;
    }

    modifier onlyBridge() {
        _requireBridge();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function mint(address to, uint tokenId) external onlyBridge {
        _safeMint(to, tokenId);
    }

    function burn(uint tokenId) external onlyBridge {
        _burn(tokenId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function bridge() external view returns(address) {
        return _getStorage().bridge;
    }

    function parent() external pure returns(address token, uint16 chainId) {
        ChildERC721Storage memory $ = _getStorage();
        return ($.parentToken, $.parentChainId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _baseURI() internal pure override returns (string memory) {
        ChildERC721Storage memory $ = _getStorage();
        return $.baseURI;
    }

    function _getStorage() private pure returns (ChildERC721Storage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := CHILDERC721_STORAGE_LOCATION
        }
    }

    function _requireBridge() internal view {
        if (this.bridge() != msg.sender) {
            revert NotBridge();
        }
    }
}