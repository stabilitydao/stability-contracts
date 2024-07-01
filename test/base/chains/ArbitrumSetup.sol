// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../../chains/ArbitrumLib.sol";
import "../ChainSetup.sol";
import "../../../src/core/Platform.sol";
import "../../../src/core/Factory.sol";
import {DeployCore} from "../../../script/base/DeployCore.sol";

abstract contract ArbitrumSetup is ChainSetup, DeployCore {
    bool public showDeployLog;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("ARBITRUM_RPC_URL")));
        vm.rollFork(227575716);
    }

    function testArbitrumSetupStub() external {}

    function _init() internal override {
        //region ----- DeployCore.sol -----
        platform = Platform(_deployCore(ArbitrumLib.platformDeployParams()));
        ArbitrumLib.deployAndSetupInfrastructure(address(platform), showDeployLog);
        factory = Factory(address(platform.factory()));
        //endregion -- DeployCore.sol ----
    }

    function _deal(address token, address to, uint amount) internal override {
        if (token == ArbitrumLib.TOKEN_USDC) {
            vm.prank(0x2Df1c51E09aECF9cacB7bc98cB1742757f163dF7);
            IERC20(token).transfer(to, amount);
        } else {
            deal(token, to, amount);
        }
    }
}
