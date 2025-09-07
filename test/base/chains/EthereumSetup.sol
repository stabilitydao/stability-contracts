// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {EthereumLib} from "../../../chains/EthereumLib.sol";
import {ChainSetup} from "../ChainSetup.sol";
import {Platform} from "../../../src/core/Platform.sol";
import {Factory} from "../../../src/core/Factory.sol";
import {DeployCore} from "../../../script/base/DeployCore.sol";

abstract contract EthereumSetup is ChainSetup, DeployCore {
    bool public showDeployLog;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("ETHEREUM_RPC_URL")));
        vm.rollFork(21680000); // Jan-22-2025 12:22:23 PM
    }

    function testSetupStub() external {}

    function _init() internal override {
        //region ----- DeployCore.sol -----
        platform = Platform(_deployCore(EthereumLib.platformDeployParams()));
        EthereumLib.deployAndSetupInfrastructure(address(platform), showDeployLog);
        factory = Factory(address(platform.factory()));
        //endregion
    }

    function _deal(address token, address to, uint amount) internal override {
        deal(token, to, amount);
    }
}
