// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IOFTPausable} from "./IOFTPausable.sol";

interface ITokenOFTAdapter is IOFTPausable {
    function initialize(address platform_) external;
}
