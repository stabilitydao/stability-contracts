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
        // vm.rollFork(910000); // Oct 25 2024 23:54:31 PM (+03:00 UTC)
        vm.rollFork(936000);
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
        if (token == RealLib.TOKEN_arcUSD) {
            vm.prank(0xA3949263535D40d470132Ab6CA76b16D6183FD31); // stack vault
            IERC20(token).transfer(to, amount + 1); // need for this token
        } else if (token == RealLib.TOKEN_UKRE) {
            vm.prank(0x72c20EBBffaE1fe4E9C759b326D97763E218F9F6); // top1 holder
            IERC20(token).transfer(to, amount);
        } else if (token == RealLib.TOKEN_DAI) {
            vm.prank(0x4f5c568F72369ff4Ce4e53d797985DFFBdA6FC71); // pearl pool
            IERC20(token).transfer(to, amount);
        } else if (token == RealLib.TOKEN_USTB) {
            vm.prank(0x561F2826A9d2A653fdC903A9effa23c0C0c3B549); // stack vault
            IERC20(token).transfer(to, amount);
        } else {
            deal(token, to, amount);
        }
    }
}
