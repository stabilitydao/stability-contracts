// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../../chains/SonicLib.sol";
import "../ChainSetup.sol";
import "../../../src/core/Platform.sol";
import "../../../src/core/Factory.sol";
import {IPoolMinimal} from "../../../src/integrations/aave/IPoolMinimal.sol";
import {DeployCore} from "../../../script/base/DeployCore.sol";

abstract contract SonicSetup is ChainSetup, DeployCore {
    bool public showDeployLog;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        // vm.rollFork(489000); // Dec-16-2024 06:18:01 PM +UTC
        // vm.rollFork(850000); // Dec 20, 2024, 12:56 PM GMT+3
        // vm.rollFork(1168500); // Dec-22-2024 10:34:43 UTC
        // vm.rollFork(1462000); // Dec-24-2024 12:35:56 PM +UTC
        // vm.rollFork(1901000); // Dec-29-2024 12:45:51 PM +UTC
        // vm.rollFork(2026000); // Dec-30-2024 08:07:33 PM +UTC
        // vm.rollFork(2702000); // Jan-06-2025 11:41:18 AM +UTC
        // vm.rollFork(3273000); // Jan-10-2025 03:49:56 PM +UTC
        // vm.rollFork(3292762); // Jan-10-2025 07:11:31 PM +UTC
        vm.rollFork(5169000); // Jan-23-2025 07:56:29 PM
            // vm.rollFork(5715000); // Jan-28-2025 09:03:09 PM +UTC
    }

    function testSetupStub() external {}

    function _init() internal override {
        //region ----- DeployCore.sol -----
        platform = Platform(_deployCore(SonicLib.platformDeployParams()));
        SonicLib.deployAndSetupInfrastructure(address(platform), showDeployLog);
        factory = Factory(address(platform.factory()));
        //endregion ----- DeployCore.sol -----
    }

    function _deal(address token, address to, uint amount) internal override {
        if (token == SonicLib.TOKEN_auUSDC) {
            address aurumPool = 0x69f196a108002FD75d4B0a1118Ee04C065a63dE9;
            deal(SonicLib.TOKEN_USDC, address(this), amount);
            IERC20(SonicLib.TOKEN_USDC).approve(aurumPool, amount);
            IPoolMinimal(aurumPool).supply(SonicLib.TOKEN_USDC, amount, address(this), 0);
        } else {
            deal(token, to, amount);
        }
    }
}
