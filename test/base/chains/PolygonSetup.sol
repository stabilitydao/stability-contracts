// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../../chains/PolygonLib.sol";
import "../ChainSetup.sol";
import "../../../src/core/Platform.sol";
import "../../../src/core/Factory.sol";

abstract contract PolygonSetup is ChainSetup {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("POLYGON_RPC_URL")));
        vm.rollFork(48098000); // Sep-01-2023 03:23:25 PM +UTC
    }

    function testPolygonSetupStub() external {}

    function _init() internal override {
        //region ----- DeployPlatform -----
        platform = Platform(PolygonLib.runDeploy(false));
        factory = Factory(address(platform.factory()));
        //endregion -- DeployPlatform ----
    }
}
