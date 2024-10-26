// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../../chains/RealLib.sol";
import "../ChainSetup.sol";
import "../../../src/core/Platform.sol";
import "../../../src/core/Factory.sol";
import {DeployCore} from "../../../script/base/DeployCore.sol";

abstract contract RealSetup is ChainSetup, DeployCore {
    bool public showDeployLog;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("REAL_RPC_URL")));
        vm.rollFork(910000); // Oct 25 2024 23:54:31 PM (+03:00 UTC)
    }

    function testSetupStub() external {}

    function _init() internal override {
        //region ----- DeployCore.sol -----
        platform = Platform(_deployCore(RealLib.platformDeployParams()));
        RealLib.deployAndSetupInfrastructure(address(platform), showDeployLog);
        factory = Factory(address(platform.factory()));
        //endregion -- DeployCore.sol -----
    }

    function _deal(address token, address to, uint amount) internal override {
        deal(token, to, amount);
    }
}
