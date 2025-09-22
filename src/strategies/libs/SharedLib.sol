// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {CommonLib} from "../../core/libs/CommonLib.sol";
import {IFactory} from "../../interfaces/IFactory.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
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

    /// @notice Universal implementation of {initVariants} for all farms
    /// @param platform_ Platform address
    /// @param strategyLogicId Strategy logic ID to filter farms
    /// @param _genDesc Function to generate the variant description from the farm data
    /// @return variants Array of variant descriptions
    /// @return addresses Array of farm addresses
    function initVariantsForFarm(
        address platform_,
        string memory strategyLogicId,
        function(IFactory.Farm memory) internal view returns (string memory) _genDesc
    )
        internal
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        addresses = new address[](0);
        ticks = new int24[](0);
        IFactory.Farm[] memory farms = IFactory(IPlatform(platform_).factory()).farms();
        uint len = farms.length;
        //slither-disable-next-line uninitialized-local
        uint _total;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = farms[i];
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyLogicId)) {
                ++_total;
            }
        }
        variants = new string[](_total);
        nums = new uint[](_total);
        _total = 0;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = farms[i];
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyLogicId)) {
                nums[_total] = i;
                variants[_total] = _genDesc(farm);
                ++_total;
            }
        }
    }
}
