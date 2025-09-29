// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ChainSetup} from "../ChainSetup.sol";
import {DeployCore} from "../../../script/base/DeployCore.sol";
import {Factory} from "../../../src/core/Factory.sol";
import {Platform} from "../../../src/core/Platform.sol";
import {PlasmaConstantsLib} from "../../../chains/plasma/PlasmaConstantsLib.sol";
import {PlasmaLib} from "../../../chains/plasma/PlasmaLib.sol";

abstract contract PlasmaSetup is ChainSetup, DeployCore {
    /// @dev Test BalancerV3ReCLAMMAdapterTest uses values from UI for the given block
    // If you are going to change the block please fix constants in BalancerV3ReCLAMMAdapterTest too
    uint internal constant FORK_BLOCK = 2196726; // Sep-29-2025 06:05:08 UTC

    bool public showDeployLog;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("PLASMA_RPC_URL")));
        vm.rollFork(FORK_BLOCK);
    }

    function testSetupStub() external {}

    function _init() internal override {
        platform = Platform(_deployCore(PlasmaLib.platformDeployParams()));
        PlasmaLib.deployAndSetupInfrastructure(address(platform));
        factory = Factory(address(platform.factory()));
    }

    function _deal(address token, address to, uint amount) internal virtual override {
        deal(token, to, amount);
    }
}
