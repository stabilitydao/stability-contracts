// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IEVault} from "../../integrations/euler/IEVault.sol";
import {UniswapV3MathLib} from "../libs/UniswapV3MathLib.sol";
import {IUniswapV3Pool} from "../../integrations/uniswapv3/IUniswapV3Pool.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {IFarmingStrategy} from "../../interfaces/IFarmingStrategy.sol";
import {IFactory} from "../../interfaces/IFactory.sol";
import {StrategyLib} from "./StrategyLib.sol";
import {CommonLib} from "../../core/libs/CommonLib.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IMerklDistributor} from "../../integrations/merkl/IMerklDistributor.sol";
import {console} from "forge-std/console.sol";

/// @title Library for EMF strategy code splitting
library EMFLib {
    using SafeERC20 for IERC20;

    function initVariants(address platform_, string memory strategyLogicId) external view
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
}
