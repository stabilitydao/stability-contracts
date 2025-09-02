// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console, Test} from "forge-std/Test.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {UpgradeHelper} from "../../src/periphery/UpgradeHelper.sol";

contract UpgradeHelperTestSonic is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    UpgradeHelper public immutable upgradeHelper;

    constructor() {
        // Jun-26-2025 08:22:08 PM +UTC
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 36063061));
        upgradeHelper = new UpgradeHelper(PLATFORM);
    }

    function test_upgrade_vaults() public {
        uint upgraded = upgradeHelper.upgradeVaults();
        //console.log(upgraded);
        assertEq(upgraded, 76);
        upgraded = upgradeHelper.upgradeVaults();
        assertEq(upgraded, 0);
    }

    function test_upgrade_strategies() public {
        uint upgraded = upgradeHelper.upgradeStrategies();
        //console.log(upgraded);
        assertEq(upgraded, 40);
        upgraded = upgradeHelper.upgradeStrategies();
        assertEq(upgraded, 0);
    }
}
