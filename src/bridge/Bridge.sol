// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../core/base/Controllable.sol";
import "../interfaces/IBridge.sol";
import "../interfaces/IChildERC20.sol";
import "../interfaces/IChildERC721.sol";
import "../interfaces/IChildTokenFactory.sol";
import "./lzApp/NonblockingLzApp.sol";

/// @title Stability Bridge
/// @author Jude (https://github.com/iammrjude)
contract Bridge is Controllable, IBridge, NonblockingLzApp {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    bytes public constant PAYLOAD = "\x01\x02\x03\x04";

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.Bridge")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant BRIDGE_STORAGE_LOCATION =
        0x052cfeb6b58cb7c758df4b774795a7771143349338d88867c9a9d655662bfd00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.Bridge
    struct BridgeStorage {
        mapping(bytes32 linkHash => Link) link;
        Link[] links;
        address childTokenFactory;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(address platform_, address _lzEndpoint) external initializer {
        __Controllable_init(platform_);
        __NonblockingLzApp_init(_lzEndpoint);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBridge
    function chainId() external view returns (uint64) {
        return uint64(block.chainid);
    }

    /// @inheritdoc IBridge
    function link(bytes32 linkHash) external view returns (Link memory) {
        return _getStorage().link[linkHash];
    }

    /// @inheritdoc IBridge
    function links() external view returns (Link[] memory) {
        return _getStorage().links;
    }

    /// @inheritdoc IBridge
    function adapterStatus(string memory adapterId) external view returns (bool active, uint priority) {}

    /// @inheritdoc IBridge
    function adapters() external view returns (string[] memory) {}

    /// @inheritdoc IBridge
    function getTarget(address token, uint64 chainTo) external view returns (address targetToken, bytes32 linkHash) {}

    function estimateFee(
        uint16 _dstChainId,
        bool _useZro,
        bytes calldata _adapterParams
    ) public view returns (uint nativeFee, uint zroFee) {
        return lzEndpoint.estimateFees(_dstChainId, address(this), PAYLOAD, _useZro, _adapterParams);
    }

    function getOracle(uint16 remoteChainId) external view returns (address _oracle) {
        bytes memory bytesOracle =
            lzEndpoint.getConfig(lzEndpoint.getSendVersion(address(this)), remoteChainId, address(this), 6);
        assembly {
            _oracle := mload(add(bytesOracle, 32))
        }
    }

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

    function setChildTokenFactory(address childTokenFactory_) external onlyOperator {
        BridgeStorage storage $ = _getStorage();
        $.childTokenFactory = childTokenFactory_;
    }

    /// @inheritdoc IBridge
    function enableAdapter(string memory adapterId) external {}

    function lockToken(address token, uint amountOrTokenId, uint16 chainTo, bool nft) public payable {
        if (nft) {
            IERC721(token).safeTransferFrom(msg.sender, address(this), amountOrTokenId);
        } else {
            bool success = IERC20(token).transferFrom(msg.sender, address(this), amountOrTokenId);
            if (!success) revert TokenTransferFailed();
        }
        bytes memory payload = abi.encode(msg.sender, amountOrTokenId, token, nft, true);
        _lzSend(chainTo, payload, payable(msg.sender), address(0x0), bytes(""), msg.value);
    }

    function burnToken(address token, uint amountOrTokenId, uint16 chainTo, bool nft) public payable {
        if (nft) {
            IChildERC721(token).burn(amountOrTokenId);
        } else {
            IChildERC20(token).burn(msg.sender, amountOrTokenId);
        }
        bytes memory payload = abi.encode(msg.sender, amountOrTokenId, token, nft, false);
        _lzSend(chainTo, payload, payable(msg.sender), address(0x0), bytes(""), msg.value);
    }

    function setOracle(uint16 dstChainId, address oracle) external onlyOwner {
        uint TYPE_ORACLE = 6;
        // set the Oracle
        lzEndpoint.setConfig(lzEndpoint.getSendVersion(address(this)), dstChainId, TYPE_ORACLE, abi.encode(oracle));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getStorage() private pure returns (BridgeStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := BRIDGE_STORAGE_LOCATION
        }
    }

    function mintToken(address token, address to, uint amountOrTokenId, bool nft) internal {
        if (nft) {
            IChildERC721(token).mint(to, amountOrTokenId);
        } else {
            IChildERC20(token).mint(to, amountOrTokenId);
        }
    }

    function unlockToken(address token, address to, uint amountOrTokenId, bool nft) internal {
        if (nft) {
            IERC721(token).safeTransferFrom(address(this), to, amountOrTokenId);
        } else {
            bool success = IERC20(token).transfer(to, amountOrTokenId);
            if (!success) revert TokenTransferFailed();
        }
    }

    function _nonblockingLzReceive(uint16, bytes memory, uint64, bytes memory _payload) internal override {
        (address toAddress, uint amountOrTokenId, address token, bool nft, bool mint) =
            abi.decode(_payload, (address, uint, address, bool, bool));
        address childToken = IChildTokenFactory(_getStorage().childTokenFactory).getChildTokenOf(token);
        address parentToken = IChildTokenFactory(_getStorage().childTokenFactory).getParentTokenOf(token);
        if (mint) mintToken(childToken, toAddress, amountOrTokenId, nft);
        if (!mint) unlockToken(parentToken, toAddress, amountOrTokenId, nft);
    }
}
