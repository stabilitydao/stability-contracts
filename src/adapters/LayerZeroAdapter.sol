// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../core/base/Controllable.sol";
import "../interfaces/IInterChainAdapter.sol";
import "../interfaces/IChildTokenFactory.sol";
import "./base/NonblockingLzApp.sol";
import "./libs/InterChainAdapterIdLib.sol";

/// @author Jude (https://github.com/iammrjude)
contract LayerZeroAdapter is Controllable, IInterChainAdapter, NonblockingLzApp {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    bytes public constant PAYLOAD = "\x01\x02\x03\x04";

    /// @dev Version of LayerZeroAdapter implementation
    string public constant VERSION = "1.0.0";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(address platform_, address _lzEndpoint) external initializer {
        __Controllable_init(platform_);
        __NonblockingLzApp_init(_lzEndpoint);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IInterChainAdapter
    function sendMessage(Message memory message) external {}

    /// @inheritdoc IInterChainAdapter
    function interChainAdapterId() external returns (string memory) {
        return InterChainAdapterIdLib.LAYERZERO;
    }

    function setOracle(uint16 dstChainId, address oracle) external onlyOwner {
        uint TYPE_ORACLE = 6;
        // set the Oracle
        lzEndpoint.setConfig(lzEndpoint.getSendVersion(address(this)), dstChainId, TYPE_ORACLE, abi.encode(oracle));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IInterChainAdapter
    function endpoint() external view returns (address) {
        return address(lzEndpoint);
    }

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
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _nonblockingLzReceive(uint16, bytes memory, uint64, bytes memory _payload) internal override {
        (address toAddress, uint amountOrTokenId, address token, bool nft, bool mint) =
            abi.decode(_payload, (address, uint, address, bool, bool));
        // address childToken = IChildTokenFactory(_getStorage().childTokenFactory).getChildTokenOf(token);
        // address parentToken = IChildTokenFactory(_getStorage().childTokenFactory).getParentTokenOf(token);
        // if (mint) mintToken(childToken, toAddress, amountOrTokenId, nft);
        // if (!mint) unlockToken(parentToken, toAddress, amountOrTokenId, nft);
    }
}
