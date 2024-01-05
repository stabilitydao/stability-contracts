// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../../chains/PolygonLib.sol";
import "../ChainSetup.sol";
import "../../../src/core/Platform.sol";
import "../../../src/core/Factory.sol";

abstract contract PolygonSetup is ChainSetup {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("POLYGON_RPC_URL")));
        // vm.rollFork(48098000); // Sep-01-2023 03:23:25 PM +UTC
        vm.rollFork(51800000); // Jan-01-2024 02:33:32 AM +UTC
    }

    function testPolygonSetupStub() external {}

    function _init() internal override {
        //region ----- DeployPlatform -----
        platform = Platform(PolygonLib.runDeploy(false));
        factory = Factory(address(platform.factory()));
        //endregion -- DeployPlatform ----
    }

    function _deal(address token, address to, uint amount) internal override {
        if (token == PolygonLib.TOKEN_USDC) {
            vm.prank(0x72A53cDBBcc1b9efa39c834A540550e23463AAcB); // Cryoto.com
            IERC20(token).transfer(to, amount);
        } else {
            deal(token, to, amount);
        }
    }
}
