// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title Interface of the proxy contract that is used to read a specific API3
/// data feed
/// @notice While reading API3 data feeds, users are strongly recommended to
/// use this interface to interact with data feed-specific proxy contracts,
/// rather than accessing the underlying contracts directly
interface IApi3ReaderProxy {
    /// @notice Returns the current value and timestamp of the API3 data feed
    /// associated with the proxy contract
    /// @dev The user is responsible for validating the returned data. For
    /// example, if `value` is the spot price of an asset, it would be
    /// reasonable to reject values that are not positive.
    /// `timestamp` does not necessarily refer to a timestamp of the chain that
    /// the read proxy is deployed on. Considering that it may refer to an
    /// off-chain time (such as the system time of the data sources, or the
    /// timestamp of another chain), the user should not expect it to be
    /// strictly bounded by `block.timestamp`.
    /// Considering that the read proxy contract may be upgradeable, the user
    /// should not assume any hard guarantees about the behavior in general.
    /// For example, even though it may sound reasonable to expect `timestamp`
    /// to never decrease over time and the current implementation of the proxy
    /// contract guarantees it, technically, an upgrade can cause `timestamp`
    /// to decrease. Therefore, the user should be able to handle any change in
    /// behavior, which may include reverting gracefully.
    /// @return value Data feed value
    /// @return timestamp Data feed timestamp
    function read() external view returns (int224 value, uint32 timestamp);
}
