// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../../chains/BaseLib.sol";
import "../ChainSetup.sol";
import "../../../src/core/Platform.sol";
import "../../../src/core/Factory.sol";

abstract contract BaseSetup is ChainSetup {
    bool public showDeployLog;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("BASE_RPC_URL")));
//        vm.rollFork(55000000);
    }

    function testSetupStub() external {}

    function _init() internal override {
        //region ----- DeployPlatform -----
        platform = Platform(BaseLib.runDeploy(showDeployLog));
        factory = Factory(address(platform.factory()));
        //endregion -- DeployPlatform ----
    }

    function _deal(address token, address to, uint amount) internal override {
        if (token == BaseLib.TOKEN_USDC) {
            vm.prank(0x3304E22DDaa22bCdC5fCa2269b418046aE7b566A);
            IERC20(token).transfer(to, amount);
        } else {
            deal(token, to, amount);
        }
    }
}
