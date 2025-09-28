// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ChainSetup} from "../ChainSetup.sol";
import {DeployCore} from "../../../script/base/DeployCore.sol";
import {Factory} from "../../../src/core/Factory.sol";
import {Platform} from "../../../src/core/Platform.sol";
import {IPlatform} from "../../../src/interfaces/IPlatform.sol";
import {PlasmaConstantsLib} from "../../../chains/plasma/PlasmaConstantsLib.sol";
import {PlasmaLib} from "../../../chains/plasma/PlasmaLib.sol";

abstract contract PlasmaSetup is ChainSetup, DeployCore {
    bool public showDeployLog;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("PLASMA_RPC_URL")));
        vm.rollFork(2140000); // Sep-28-2025 14:19:42 UTC
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
