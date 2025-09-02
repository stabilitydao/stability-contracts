// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommonLib} from "../../core/libs/CommonLib.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IFactory} from "../../interfaces/IFactory.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {ISiloConfig} from "../../integrations/silo/ISiloConfig.sol";
import {ISilo} from "../../integrations/silo/ISilo.sol";
import {StrategyIdLib} from "./StrategyIdLib.sol";

/// @notice Library for Silo ALMF strategy - additional functions that didn't fit to SiloALMFLib
library SiloALMFLib2 {
    uint public constant FARM_ADDRESS_LENDING_VAULT_INDEX = 0;
    uint public constant FARM_ADDRESS_BORROWING_VAULT_INDEX = 1;
    uint public constant FARM_ADDRESS_FLASH_LOAN_VAULT_INDEX = 2;
    uint public constant FARM_ADDRESS_SILO_LENS_INDEX = 3;

    function initVariants(address platform_)
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
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, StrategyIdLib.SILO_ALMF_FARM)) {
                ++_total;
            }
        }
        variants = new string[](_total);
        nums = new uint[](_total);
        _total = 0;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = farms[i];
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, StrategyIdLib.SILO_ALMF_FARM)) {
                nums[_total] = i;
                variants[_total] = _generateDescription(
                    farm.addresses[FARM_ADDRESS_LENDING_VAULT_INDEX],
                    IERC4626(farm.addresses[FARM_ADDRESS_LENDING_VAULT_INDEX]).asset(),
                    IERC4626(farm.addresses[FARM_ADDRESS_BORROWING_VAULT_INDEX]).asset()
                );
                ++_total;
            }
        }
    }

    function _generateDescription(
        address lendingVault,
        address collateralAsset,
        address borrowAsset
    ) public view returns (string memory) {
        uint siloId = ISiloConfig(ISilo(lendingVault).config()).SILO_ID();
        return string.concat(
            "Supply ",
            IERC20Metadata(collateralAsset).symbol(),
            " and borrow ",
            IERC20Metadata(borrowAsset).symbol(),
            " on Silo V2 market ",
            CommonLib.u2s(siloId),
            " with leverage looping"
        );
    }
}
