// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IOFTPausable} from "./IOFTPausable.sol";

interface IBridgedToken is IOFTPausable {
    event BridgedTokenName(string newName);
    event BridgedTokenSymbol(string newSymbol);

    /// @param delegate_ The delegate capable of making OApp configurations inside of the endpoint.
    /// Pass 0 to set multisig as the delegate. Owner (multisig) is able to change it using setDelegate.
    function initialize(address platform_, string memory name_, string memory symbol_, address delegate_) external;

    /// @notice Sets a new name for the token.
    function setName(string calldata newName) external;

    /// @notice Sets a new symbol for the token.
    function setSymbol(string calldata newSymbol) external;
}
