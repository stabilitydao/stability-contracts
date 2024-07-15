// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/Strings.sol";
import "./ALMPositionNameLib.sol";
import "../../core/libs/CommonLib.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IAmmAdapter.sol";

library SQMFLib {
    function generateDescription(
        IFactory.Farm memory farm,
        IAmmAdapter ammAdapter
    ) external view returns (string memory) {
        //slither-disable-next-line calls-loop
        return string.concat(
            "Earn ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(farm.rewardAssets), ", "),
            " on QuickSwap V3 by ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(ammAdapter.poolTokens(farm.pool)), "-"),
            " Steer ",
            //slither-disable-next-line calls-loop
            ALMPositionNameLib.getName(farm.nums[0]),
            " strategy ",
            shortAddress(farm.addresses[0])
        );
    }

    function shortAddress(address addr) public pure returns (string memory) {
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
