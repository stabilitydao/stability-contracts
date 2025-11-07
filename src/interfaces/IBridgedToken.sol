// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IOFTPausable} from "./IOFTPausable.sol";

interface IBridgedToken is IOFTPausable {
    function initialize(address platform_, string memory name_, string memory symbol_) external;
}
