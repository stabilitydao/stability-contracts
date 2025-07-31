// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Interface for a proxy-enabled bridge contract that locks/unlocks an existing ERC20 token using LayerZero v2.
interface IBridgeTokenAdapter {
    /// ------------------------------------- Read functions

    /// @notice Checks if a message is currently blocked.
    /// @param srcAddress_ The source contract address.
    /// @param nonce_ The message nonce.
    /// @return bool `true` if the message is blocked.
    function isBlocked(address srcAddress_, uint64 nonce_) external view returns (bool);

    /// @notice Quotes the native token cost for a cross-chain call.
    /// @param amount_ The amount of tokens to send.
    /// @param options_ The LayerZero options (e.g., for specifying gas).
    /// @return nativeFee The cost in native currency.
    function quote(uint amount_, bytes calldata options_) external view returns (uint nativeFee);

    /// @notice Returns the address of the underlying ERC20 token.
    function token() external view returns (address);

    /// @notice Returns the total amount of tokens currently locked in the contract.
    function totalLocked() external view returns (uint);

    /// @return eid The destination endpoint ID.
    /// @return peer Trusted remote address (peer) for destination chain.
    /// @return options The LayerZero options to enforce.
    function getConfig() external view returns (uint32 eid, address peer, bytes memory options);

    /// ------------------------------------- Write functions
    /// @notice Initializes the contract. Called once after the proxy is deployed.
    /// @param token_ The address of the ERC20 token to be bridged.
    /// @param lzEndpoint_ The address of the LayerZero-v2 Endpoint in the current chain.
    function init(address platform_, address token_, address lzEndpoint_) external;

    /// @notice Configures enforced options for messages to a specific chain.
    /// @dev Used to enable guaranteed message ordering.
    /// @custom:access Owner only
    /// @param eid_ The destination endpoint ID.
    /// @param peer_ Trusted remote address (peer) for destination chain.
    /// @param options_ The LayerZero options to enforce.
    function setConfig(uint32 eid_, address peer_, bytes calldata options_) external;

    /// @notice Sends tokens to another chain.
    /// @dev The user must first approve the contract to spend the specified amount.
    /// @dev The call must include a native token value equal to `nativeFee` from `quote()`.
    /// @param destTo_ The recipient's address on the destination chain.
    /// @param amount_ The amount of tokens to send.
    /// @param options_ The LayerZero options.
    function send(address destTo_, uint amount_, bytes calldata options_) external payable;

    //  /// @notice Retries a blocked message.
    //  /// @custom:access Owner only
    //  /// @param srcAddress_ The source contract address.
    //  /// @param nonce_ The message nonce.
    //  /// @param payload_ The message payload.
    //  function retryMessage(address srcAddress_, uint64 nonce_, bytes calldata payload_) external payable;
    //
    //  /// @notice Skips (deletes) a blocked message.
    //  /// @custom:access Owner only
    //  /// @param srcAddress_ The source contract address.
    //  /// @param nonce_ The message nonce.
    //  function skipMessage(address srcAddress_, uint64 nonce_) external;

    /// @notice Rescues accidentally sent ERC20 tokens from the contract's balance.
    /// @custom:access Owner only
    /// @param tokenAddress_ The address of the token to rescue.
    /// @param to_ The address to send the rescued tokens to.
    /// @param amount_ The amount to rescue.
    function salvage(address tokenAddress_, address to_, uint amount_) external;

    /// @notice Withdraws native currency (e.g., ETH, AVAX) from the contract's balance.
    /// @custom:access Owner only
    /// @param to_ The address to send the native currency to.
    /// @param amount_ The amount to withdraw.
    function withdrawNative(address to_, uint amount_) external;
}
