// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IOFTPausable} from "./IOFTPausable.sol";

interface ITokenOFTAdapter is IOFTPausable {
    /// @param delegate_ The delegate capable of making OApp configurations inside of the endpoint.
    /// Pass 0 to set multisig as the delegate. Owner (multisig) is able to change it using setDelegate.
    function initialize(address platform_, address delegate_) external;
}
