// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../core/base/Controllable.sol";
import "../interfaces/IBooster.sol";
import "../interfaces/ILiquidToken.sol";
import "../integrations/retro/IVotingEscrow.sol";

/// @notice veRETRO holder
/// @author Alien Deployer (https://github.com/a17)
contract RetroBooster is Controllable, IBooster, IERC721Receiver {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // todo set
    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.RetroBooster")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant RETRO_BOOSTER_STORAGE_LOCATION =
        0x263d5089de5bb3f97c8effd51f1a153b36e97065a51e67a94885830ed03a7a00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.RetroBooster
    struct RetroBoosterStorage {
        /// @inheritdoc IBooster
        address token;
        /// @inheritdoc IBooster
        address veToken;
        /// @inheritdoc IBooster
        address veUnderlying;
        /// @inheritdoc IBooster
        uint veTokenId;
        /// @inheritdoc IBooster
        uint lastRefresh;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(
        address platform_,
        address token_,
        address veToken_,
        address veUnderlying_
    ) public initializer {
        __Controllable_init(platform_);
        RetroBoosterStorage storage $ = _getStorage();
        $.token = token_;
        $.veToken = veToken_;
        $.veUnderlying = veUnderlying_;
        // todo event
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CALLBACKS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC721Receiver
    function onERC721Received(address, address from, uint tokenId, bytes calldata) external returns (bytes4) {
        RetroBoosterStorage storage $ = _getStorage();
        address ve = $.veToken;
        if (ve == msg.sender) {
            uint _tokenId = $.veTokenId;
            uint locked = uint(int(IVotingEscrow(ve).locked(tokenId).amount));
            if (_tokenId == 0) {
                $.veTokenId = tokenId;
            } else {
                IVotingEscrow(ve).merge(tokenId, _tokenId);
            }
            ILiquidToken($.token).mint(locked, from);
        }

        return IERC721Receiver.onERC721Received.selector;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     WRITE FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBooster
    function refresh() external {
        // todo
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBooster
    function token() external view returns (address) {
        return _getStorage().token;
    }

    /// @inheritdoc IBooster
    function veToken() external view returns (address) {
        return _getStorage().veToken;
    }

    /// @inheritdoc IBooster
    function veUnderlying() external view returns (address) {
        return _getStorage().veUnderlying;
    }

    /// @inheritdoc IBooster
    function veTokenId() external view returns (uint) {
        return _getStorage().veTokenId;
    }

    /// @inheritdoc IBooster
    function lastRefresh() external view returns (uint) {
        return _getStorage().lastRefresh;
    }

    /// @inheritdoc IBooster
    function veUnderlyingAmount() external view returns (uint) {
        RetroBoosterStorage storage $ = _getStorage();
        return uint(int(IVotingEscrow($.veToken).locked($.veTokenId).amount));
    }

    /// @inheritdoc IBooster
    function power() external view returns (uint) {
        RetroBoosterStorage storage $ = _getStorage();
        return IVotingEscrow($.veToken).balanceOfNFT($.veTokenId);
    }

    /// @inheritdoc IBooster
    function needRefresh() external view returns (bool) {
        RetroBoosterStorage storage $ = _getStorage();
        IVotingEscrow ve = IVotingEscrow($.veToken);
        if (address(ve) == address(0)) {
            return false;
        }

        // todo

        return false;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getStorage() private pure returns (RetroBoosterStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := RETRO_BOOSTER_STORAGE_LOCATION
        }
    }
}
