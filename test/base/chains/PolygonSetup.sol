// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PolygonLib} from "../../../chains/PolygonLib.sol";
import {ChainSetup} from "../ChainSetup.sol";
import {Platform} from "../../../src/core/Platform.sol";
import {Factory} from "../../../src/core/Factory.sol";
import {DeployCore} from "../../../script/base/DeployCore.sol";
import {IFrontend} from "../../../src/interfaces/IFrontend.sol";
import {Frontend} from "../../../src/periphery/Frontend.sol";

abstract contract PolygonSetup is ChainSetup, DeployCore {
    IFrontend public frontend;
    bool public showDeployLog;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("POLYGON_RPC_URL", 63200001)));
        // vm.rollFork(48098000); // Sep-01-2023 03:23:25 PM +UTC
        // vm.rollFork(51800000); // Jan-01-2024 02:33:32 AM +UTC
        // vm.rollFork(54000000); // Feb-27-2024 12:56:05 AM +UTC
        // vm.rollFork(55000000); // Mar-23-2024 07:56:52 PM +UTC
        vm.rollFork(63200001); // Oct-18-2024 06:38:45 PM +UTC
    }

    function testPolygonSetupStub() external {}

    function _init() internal override {
        //region ----- DeployCore.sol -----
        platform = Platform(_deployCore(PolygonLib.platformDeployParams()));
        PolygonLib.deployAndSetupInfrastructure(address(platform), showDeployLog);
        factory = Factory(address(platform.factory()));
        frontend = new Frontend(address(platform));
        //endregion -- DeployCore.sol ----
    }

    function _deal(address token, address to, uint amount) internal override {
        if (token == PolygonLib.TOKEN_USDC) {
            vm.prank(0xf89d7b9c864f589bbF53a82105107622B35EaA40); // Bybit: Hot Wallet
            /// forge-lint: disable-next-line
            IERC20(token).transfer(to, amount);
        } else {
            deal(token, to, amount);
        }
    }
}
