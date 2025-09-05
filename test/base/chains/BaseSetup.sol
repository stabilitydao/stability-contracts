// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseLib} from "../../../chains/BaseLib.sol";
import {ChainSetup} from "../ChainSetup.sol";
import {Platform} from "../../../src/core/Platform.sol";
import {Factory} from "../../../src/core/Factory.sol";
import {DeployCore} from "../../../script/base/DeployCore.sol";

abstract contract BaseSetup is ChainSetup, DeployCore {
    bool public showDeployLog;

    constructor() {
        // Oct-31-2024 03:42:27 PM +UTC
        vm.selectFork(vm.createFork(vm.envString("BASE_RPC_URL"), 21800000));
        //vm.rollFork(21800000); // Oct-31-2024 03:42:27 PM +UTC
    }

    function testSetupStub() external {}

    function _init() internal override {
        //region ----- DeployCore.sol -----
        platform = Platform(_deployCore(BaseLib.platformDeployParams()));
        BaseLib.deployAndSetupInfrastructure(address(platform), showDeployLog);
        factory = Factory(address(platform.factory()));
        //endregion -- DeployCore.sol ----
    }

    function _deal(address token, address to, uint amount) internal override {
        if (token == BaseLib.TOKEN_USDC) {
            vm.prank(0x3304E22DDaa22bCdC5fCa2269b418046aE7b566A);
            /// forge-lint: disable-next-line
            IERC20(token).transfer(to, amount);
        } else {
            deal(token, to, amount);
        }
    }
}
