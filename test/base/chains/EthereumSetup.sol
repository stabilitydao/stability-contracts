// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../../chains/EthereumLib.sol";
import "../ChainSetup.sol";
import "../../../src/core/Platform.sol";
import "../../../src/core/Factory.sol";
import {DeployCore} from "../../../script/base/DeployCore.sol";

abstract contract EthereumSetup is ChainSetup, DeployCore {
    bool public showDeployLog;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("ETHEREUM_RPC_URL")));
        //        vm.rollFork(55000000);
    }

    function testSetupStub() external {}

    function _init() internal override {
        //region ----- DeployCore.sol -----
        platform = Platform(_deployCore(EthereumLib.platformDeployParams()));
        EthereumLib.deployAndSetupInfrastructure(address(platform), showDeployLog);
        factory = Factory(address(platform.factory()));
        //endregion -- DeployCore.sol ----
    }

    function _deal(address token, address to, uint amount) internal override {
        if (token == EthereumLib.TOKEN_USDC) {
            vm.prank(0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa);
            IERC20(token).transfer(to, amount);
        } else {
            deal(token, to, amount);
        }
    }
}
