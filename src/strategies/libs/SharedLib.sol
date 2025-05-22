// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

library SharedLib {
  function shortAddress(address addr) internal pure returns (string memory) {
    bytes memory s = bytes(Strings.toHexString(addr));
    bytes memory shortAddr = new bytes(12);
    shortAddr[0] = "0";
    shortAddr[1] = "x";
    shortAddr[2] = s[2];
    shortAddr[3] = s[3];
    shortAddr[4] = s[4];
    shortAddr[5] = s[5];
    shortAddr[6] = ".";
    shortAddr[7] = ".";
    shortAddr[8] = s[38];
    shortAddr[9] = s[39];
    shortAddr[10] = s[40];
    shortAddr[11] = s[41];
    return string(shortAddr);
  }
}
