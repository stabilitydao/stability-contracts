// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract BadUpgrade {
    function platform() external pure returns (address) {
        return address(2);
    }
}
