// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../../chains/SonicLib.sol";
import "../ChainSetup.sol";
import "../../../src/core/Platform.sol";
import "../../../src/core/Factory.sol";
import {DeployCore} from "../../../script/base/DeployCore.sol";

abstract contract SonicSetup is ChainSetup, DeployCore {
    bool public showDeployLog;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(489000); // Dec-16-2024 06:18:01 PM +UTC
    }

    function testSetupStub() external {}

    function _init() internal override {
        //region ----- DeployCore.sol -----
        platform = Platform(_deployCore(SonicLib.platformDeployParams()));
        SonicLib.deployAndSetupInfrastructure(address(platform), showDeployLog);
        factory = Factory(address(platform.factory()));
        //endregion ----- DeployCore.sol -----
    }

    function _deal(address token, address to, uint amount) internal override {
        deal(token, to, amount);
    }
}
