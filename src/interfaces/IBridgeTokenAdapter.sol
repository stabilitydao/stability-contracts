// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Interface for a proxy-enabled bridge contract that locks/unlocks an existing ERC20 token using LayerZero v2.
interface IBridgeTokenAdapter {
  /// @notice Initializes the contract. Called once after the proxy is deployed.
  /// @param token_ The address of the ERC20 token to be bridged.
  /// @param lzEndpoint_ The address of the LayerZero-v2 Endpoint in the current chain.
  /// @param owner_ The address of the new contract owner.
  function initialize(address platform_,  address token_, address lzEndpoint_, address owner_) external;

  /// @notice Quotes the native token cost for a cross-chain call.
  /// @param dstEid_ The LayerZero destination endpoint ID.
  /// @param amount_ The amount of tokens to send.
  /// @param options_ The LayerZero options (e.g., for specifying gas).
  /// @param useZro_ A flag indicating whether to pay fees in ZRO.
  /// @return nativeFee The cost in native currency.
  /// @return zroFee The cost in ZRO.
  function quote(
    uint32 dstEid_,
    uint256 amount_,
    bytes calldata options_,
    bool useZro_
  ) external view returns (uint256 nativeFee, uint256 zroFee);

  /// @notice Sends tokens to another chain.
  /// @dev The user must first approve the contract to spend the specified amount.
  /// @dev The call must include a native token value equal to `nativeFee` from `quote()`.
  /// @param dstEid_ The LayerZero destination endpoint ID.
  /// @param toAddress_ The recipient's address on the destination chain (in bytes32 format).
  /// @param amount_ The amount of tokens to send.
  /// @param options_ The LayerZero options.
  function send(
    uint32 dstEid_,
    bytes32 toAddress_,
    uint256 amount_,
    bytes calldata options_
  ) external payable;

  /// @notice Sets the trusted remote address (peer) for a destination chain.
  /// @dev Can only be called by the owner.
  /// @param eid_ The destination endpoint ID.
  /// @param peer_ The peer's address in bytes32 format.
  function setPeer(uint32 eid_, bytes32 peer_) external;

  /// @notice Configures enforced options for messages to a specific chain.
  /// @dev Used to enable guaranteed message ordering.
  /// @dev Can only be called by the owner.
  /// @param eid_ The destination endpoint ID.
  /// @param options_ The LayerZero options to enforce.
  function setEnforcedOptions(uint32 eid_, bytes calldata options_) external;

  /// @notice Rescues accidentally sent ERC20 tokens from the contract's balance.
  /// @dev Can only be called by the owner.
  /// @param tokenAddress_ The address of the token to rescue.
  /// @param to_ The address to send the rescued tokens to.
  /// @param amount_ The amount to rescue.
  function rescueERC20(address tokenAddress_, address to_, uint256 amount_) external;

  /// @notice Withdraws native currency (e.g., ETH, AVAX) from the contract's balance.
  /// @dev Can only be called by the owner.
  /// @param to_ The address to send the native currency to.
  /// @param amount_ The amount to withdraw.
  function withdrawNative(address to_, uint256 amount_) external;



  /// @notice Retries a blocked message.
  /// @dev Can only be called by the owner.
  /// @param srcEid_ The source endpoint ID.
  /// @param srcAddress_ The source contract address.
  /// @param nonce_ The message nonce.
  /// @param payload_ The message payload.
  function retryMessage(
    uint32 srcEid_,
    bytes32 srcAddress_,
    uint64 nonce_,
    bytes calldata payload_
  ) external payable;

  /// @notice Skips (deletes) a blocked message.
  /// @dev Can only be called by the owner.
  /// @param srcEid_ The source endpoint ID.
  /// @param srcAddress_ The source contract address.
  /// @param nonce_ The message nonce.
  function skipMessage(uint32 srcEid_, bytes32 srcAddress_, uint64 nonce_) external;

  /// @notice Checks if a message is currently blocked.
  /// @param srcEid_ The source endpoint ID.
  /// @param srcAddress_ The source contract address.
  /// @param nonce_ The message nonce.
  /// @return bool `true` if the message is blocked.
  function isBlocked(uint32 srcEid_, bytes32 srcAddress_, uint64 nonce_) external view returns (bool);

  /// @notice Returns the address of the underlying ERC20 token.
  function token() external view returns (address);

  /// @notice Returns the total amount of tokens currently locked in the contract.
  function totalLocked() external view returns (uint256);
}