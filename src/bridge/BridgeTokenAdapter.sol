// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@layerzerolabs/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IBridgeTokenAdapter} from "../interfaces/IBridgeTokenAdapter.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Token adapter to bridge wmetaUSD to another chain using LayerZero-v2
/// @author dvpublic (https://github.com/dvpublic)
contract BridgeTokenAdapter is Controllable, IBridgeTokenAdapter {
    using SafeERC20 for IERC20;

    //region --------------------------------- Constants
    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.bridge.BridgeTokenAdapter")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant BRIDGE_TOKEN_ADAPTER_STORAGE_LOCATION = 0; // todo

    error InvalidEid();
    error InvalidPeerAddress();

    event ConfigUpdated(uint32 eid, address peer, bytes options);
    //endregion --------------------------------- Constants

    //region --------------------------------- Storage
    /// @custom:storage-location erc7201:stability.Swapper
    struct BridgeTokenAdapterStorage {
        /// @notice Address of the token that this adapter will bridge (wmetaUSD)
        address token;
        /// @notice Address of the LayerZero-v2 endpoint for cross-chain communication
        address lzEndpoint;
        /// @notice The LayerZero destination endpoint ID (it's unique ID of the destination chain)
        uint32 eid;
        /// @notice Trusted remote address (peer) for a destination chain
        address peer;
        bytes options; // todo do we need to pass it individually or can we use the same options for all messages?
    }
    //endregion --------------------------------- Storage

    //region --------------------------------- Initialization

    /// @inheritdoc IControllable
    function init(address platform_, address token_, address lzEndpoint_) external initializer {
        __Controllable_init(platform_);

        BridgeTokenAdapterStorage storage $ = _getStorage();
        $.lzEndpoint = lzEndpoint_;
        $.token = token_;
    }
    //endregion --------------------------------- Initialization

    //region --------------------------------- View
    /// @inheritdoc IBridgeTokenAdapter
    function isBlocked(address srcAddress_, uint64 nonce_) external view returns (bool) {
        return false; // todo
    }

    /// @inheritdoc IBridgeTokenAdapter
    function quote(uint amount_, bytes calldata options_) external view returns (uint nativeFee) {
        BridgeTokenAdapterStorage storage $ = _getStorage();
        bytes memory payload = abi.encode(address(0), amount_); // Use a dummy recipient for quoting

        MessagingParams memory params = MessagingParams({
            dstEid: $.eid,
            receiver: bytes32(uint(uint160($.peer))),
            message: payload,
            options: options_,
            payInLzToken: false
        });

        MessagingFee memory fee = ILayerZeroEndpointV2($.lzEndpoint).quote(params, msg.sender);
        return fee.nativeFee;
    }

    /// @inheritdoc IBridgeTokenAdapter
    function token() external view returns (address) {
        return _getStorage().token;
    }

    /// @inheritdoc IBridgeTokenAdapter
    function totalLocked() external view returns (uint) {
        BridgeTokenAdapterStorage storage $ = _getStorage();
        return IERC20($.token).balanceOf(address(this));
    }

    /// @inheritdoc IBridgeTokenAdapter
    function getConfig() external view returns (uint32 eid, address peer, bytes memory options) {
        BridgeTokenAdapterStorage storage $ = _getStorage();
        eid = $.eid;
        peer = $.peer;
        options = $.options;
    }
    //endregion --------------------------------- View

    //region --------------------------------- Restricted actions
    /// @inheritdoc IBridgeTokenAdapter
    function setConfig(uint32 eid_, address peer_, bytes calldata options_) external onlyOperator {
        require(eid_ != 0, InvalidEid());
        require(peer_ != address(0), InvalidPeerAddress());

        BridgeTokenAdapterStorage storage $ = _getStorage();
        $.eid = eid_;
        $.peer = peer_;
        $.options = options_;

        emit ConfigUpdated(eid_, peer_, options_);
    }

    /// @inheritdoc IBridgeTokenAdapter
    function salvage(address tokenAddress_, address to_, uint amount_) external onlyGovernanceOrMultisig {
        // todo
    }

    /// @inheritdoc IBridgeTokenAdapter
    function withdrawNative(address to_, uint amount_) external onlyGovernanceOrMultisig {
        // todo
    }

    //endregion --------------------------------- Restricted actions

    //region --------------------------------- Main logic
    /// @inheritdoc IBridgeTokenAdapter
    function send(address destTo_, uint amount_, bytes calldata options_) external payable {
        // todo
    }

    //endregion --------------------------------- Main logic

    //region --------------------------------- Internal logic
    function _getStorage() private pure returns (BridgeTokenAdapterStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := BRIDGE_TOKEN_ADAPTER_STORAGE_LOCATION
        }
    }
    //endregion --------------------------------- Internal logic
}
