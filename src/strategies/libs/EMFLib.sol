// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IEVault} from "../../integrations/euler/IEVault.sol";
import {IFactory} from "../../interfaces/IFactory.sol";
import {CommonLib} from "../../core/libs/CommonLib.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";

/// @title Library for EMF strategy code splitting
library EMFLib {
    using SafeERC20 for IERC20;

    function initVariants(
        address platform_,
        string memory strategyLogicId
    )
        external
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
                variants[_total] = generateDescription(farm);
                ++_total;
            }
        }
    }

    function generateDescription(IFactory.Farm memory farm) public view returns (string memory) {
        //slither-disable-next-line calls-loop
        return string.concat(
            "Lend ",
            //slither-disable-next-line calls-loop
            IERC20Metadata(IEVault(farm.addresses[1]).asset()).symbol(),
            " on Euler and earn ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(farm.rewardAssets), ", "),
            " Merkl rewards"
        );
    }

    /// @notice Modified version of AmountCapLib.resolve from Euler codebase
    /// to convert cap-values to uint256 values
    /// @dev AmountCaps are 16-bit decimal floating point values:
    /// * The least significant 6 bits are the exponent
    /// * The most significant 10 bits are the mantissa, scaled by 100
    /// * The special value of 0 means limit is not set
    ///   * This is so that uninitialized storage implies no limit
    ///   * For an actual cap value of 0, use a zero mantissa and non-zero exponent
    function _resolve(uint256 amountCap) internal pure returns (uint256) {
        if (amountCap == 0) return type(uint256).max;

        unchecked {
        // Cannot overflow because this is less than 2**256:
        //   10**(2**6 - 1) * (2**10 - 1) = 1.023e+66
            return 10 ** (amountCap & 63) * (amountCap >> 6) / 100;
        }
    }
}
