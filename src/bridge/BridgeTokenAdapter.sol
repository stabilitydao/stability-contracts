// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../core/base/Controllable.sol";

/// @title Token adapter to bridge wmetaUSD to another chain using LayerZero-v2
/// @author dvpublic (https://github.com/dvpublic)
contract BridgeTokenAdapter is Controllable {
  using SafeERC20 for IERC20;

  //region --------------------------------- Constants
  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                         CONSTANTS                          */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @inheritdoc IControllable
  string public constant VERSION = "1.0.0";

  // keccak256(abi.encode(uint256(keccak256("erc7201:stability.bridge.BridgeTokenAdapter")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 private constant BRIDGE_TOKEN_ADAPTER_STORAGE_LOCATION =
    0; // todo

  //endregion --------------------------------- Constants

  //region --------------------------------- Storage
  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                         Storage                            */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @custom:storage-location erc7201:stability.Swapper
  struct BridgeTokenAdapterStorage {
    /// @notice Address of the token that this adapter will bridge (wmetaUSD)
    address token;

    /// @notice Address of the LayerZero-v2 endpoint for cross-chain communication
    address lzEndpoint;
  }
  //endregion --------------------------------- Storage

  //region --------------------------------- Initialization
  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                      INITIALIZATION                        */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @inheritdoc IControllable
  function init(address platform_, address token_, address lzEndpoint_, address owner_) external initializer {
    __Controllable_init(platform_);

    BridgeTokenAdapterStorage storage $ = _getStorage();
    $.lzEndpoint = lzEndpoint_;
    $.token = token_;
  }
  //endregion --------------------------------- Initialization

  //region --------------------------------- Main logic

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
