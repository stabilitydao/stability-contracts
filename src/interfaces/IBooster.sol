// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IBooster {
    /// @notice Immutable booster ID
    function boosterId() external view returns (string memory);

    /// @notice Token that represents ownership shares of Booster
    function token() external view returns (address);

    /// @notice veTOKEN for holding and increasing
    function veToken() external view returns (address);

    /// @notice Token that need to be locked to mint veTOKEN
    function veUnderlying() external view returns (address);

    /// @notice Token ID of veNFT
    function veTokenId() external view returns (uint);

    /// @notice Last refresh timestamp
    function lastRefresh() external view returns (uint);

    /// @notice Total locked underlying tokens
    function veUnderlyingAmount() external view returns (uint);

    /// @notice Total voting power of holded veTOKEN
    function power() external view returns (uint);

    /// @notice Need to call refresh()
    function needRefresh() external view returns (bool);

    /// @notice Do refresh actions
    function refresh() external;
}
