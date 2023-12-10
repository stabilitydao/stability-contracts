// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../core/base/Controllable.sol";
import "../interfaces/IBridge.sol";
import "../interfaces/IChildERC20.sol";
import "../interfaces/IChildERC721.sol";
import "../interfaces/IChildTokenFactory.sol";

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
        address childTokenFactory;
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
    function chainId() external view returns(uint16) {
        return uint16(block.chainid);
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
    function getTarget(address token, uint16 chainTo) external view returns(address targetToken, bytes32 linkHash) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBridge
    function interChainTransfer(address token, uint amountOrTokenId, uint16 chainTo, bool nft, bool lock) external payable {
        // lock > mint > burn > unlock
        if (lock) lockToken(token, amountOrTokenId, chainTo, nft);
        if (!lock) burnToken(token, amountOrTokenId, chainTo, nft);
    }

    /// @inheritdoc IBridge
    function interChainReceive(uint16 srcChainId, bytes memory srcAddress, uint64 nonce, bytes memory payload) external {
        (address toAddress, uint amountOrTokenId, address token, bool nft, bool mint) = abi.decode(payload, (address,uint,address,bool,bool));
        address childToken = IChildTokenFactory(_getStorage().childTokenFactory).getChildTokenOf(token);
        address parentToken = IChildTokenFactory(_getStorage().childTokenFactory).getParentTokenOf(token);
        if (mint) mintToken(childToken, amountOrTokenId, nft);
        if (!mint) unlockToken(parentToken, amountOrTokenId, nft);
    }

    /// @inheritdoc IBridge
    function addLink(Link memory link_) external onlyOperator {
        _getStorage().links.push(link_);
    }

    /// @inheritdoc IBridge
    function setLinkAdapters(string[] memory adapterIds) external onlyOperator {}

    function setTarget(address token, uint16 chainTo, address targetToken, bytes32 linkHash) external {}

    function addAdapters(string[] memory adapterIds, uint priority) external {}

    /// @inheritdoc IBridge
    function changeAdapterPriority(string memory adapterId, uint newPriority) external onlyOperator {}

    /// @inheritdoc IBridge
    function emergencyStopAdapter(string memory adapterId, string memory reason) external onlyOperator {}

    function setChildTokenFactory(address childTokenFactory_) external onlyOperator {
        BridgeStorage storage $ = _getStorage();
        $.childTokenFactory = childTokenFactory_;
    }

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

    function lockToken(address token, uint amountOrTokenId, uint16 chainTo, bool nft) internal {
        if (nft) {
            IERC721(token).safeTransferFrom(msg.sender, address(this), amountOrTokenId);
        } else {
            bool success = IERC20(token).transferFrom(msg.sender, address(this), amountOrTokenId);
            if (!success) revert TokenTransferFailed();
        }
        bytes memory payload = abi.encode(msg.sender, amountOrTokenId, token, true);
        // _lzSend(chainTo, payload, payable(msg.sender), address(0x0), bytes(""), msg.value);
    }

    function mintToken(address token, uint amountOrTokenId, bool nft) internal {
        if (nft) {
            IChildERC721(token).mint(msg.sender, amountOrTokenId);
        } else {
            IChildERC20(token).mint(msg.sender, amountOrTokenId);
        }
    }

    function burnToken(address token, uint amountOrTokenId, uint16 chainTo, bool nft) internal {
        if (nft) {
            IChildERC721(token).burn(amountOrTokenId);
        } else {
            IChildERC20(token).burn(msg.sender, amountOrTokenId);
        }
        bytes memory payload = abi.encode(msg.sender, amountOrTokenId, token, false);
        // _lzSend(chainTo, payload, payable(msg.sender), address(0x0), bytes(""), msg.value);
    }

    function unlockToken(address token, uint amountOrTokenId, bool nft) internal {
        if (nft) {
            IERC721(token).safeTransferFrom(address(this), msg.sender, amountOrTokenId);
        } else {
            bool success = IERC20(token).transfer(msg.sender, amountOrTokenId);
            if (!success) revert TokenTransferFailed();
        }
    }

    function _nonblockingLzReceive(uint16, bytes memory, uint64, bytes memory _payload) internal {
        (address toAddress, uint amountOrTokenId, address token, bool nft, bool mint) = abi.decode(_payload, (address,uint,address,bool,bool));
        address childToken = IChildTokenFactory(_getStorage().childTokenFactory).getChildTokenOf(token);
        address parentToken = IChildTokenFactory(_getStorage().childTokenFactory).getParentTokenOf(token);
        if (mint) mintToken(childToken, amountOrTokenId, nft);
        if (!mint) unlockToken(parentToken, amountOrTokenId, nft);
    }
}