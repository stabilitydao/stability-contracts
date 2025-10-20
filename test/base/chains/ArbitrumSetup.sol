// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ArbitrumLib} from "../../../chains/ArbitrumLib.sol";
import {ChainSetup} from "../ChainSetup.sol";
import {Platform} from "../../../src/core/Platform.sol";
import {Factory} from "../../../src/core/Factory.sol";
import {DeployCore} from "../../../script/base/DeployCore.sol";

abstract contract ArbitrumSetup is ChainSetup, DeployCore {
    bool public showDeployLog;

    uint internal constant FORK_BLOCK = 227575716;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("ARBITRUM_RPC_URL"), FORK_BLOCK));
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
            /// forge-lint: disable-next-line
            IERC20(token).transfer(to, amount);
        } else {
            deal(token, to, amount);
        }
    }
}
