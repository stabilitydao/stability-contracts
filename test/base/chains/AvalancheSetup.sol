// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AvalancheLib} from "../../../chains/avalanche/AvalancheLib.sol";
import {ChainSetup} from "../ChainSetup.sol";
import {DeployCore} from "../../../script/base/DeployCore.sol";
import {Factory} from "../../../src/core/Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolMinimal} from "../../../src/integrations/aave/IPoolMinimal.sol";
import {Platform} from "../../../src/core/Platform.sol";

abstract contract AvalancheSetup is ChainSetup, DeployCore {
    bool public showDeployLog;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("AVALANCHE_RPC_URL")));
        // use block in C-chain only, see https://snowtrace.io/block/68407132?chainid=43114
        vm.rollFork(68407132); // Sep-8-2025 09:54:05 UTC
    }

    function testSetupStub() external {}

    function _init() internal override {
        platform = Platform(_deployCore(AvalancheLib.platformDeployParams()));
        AvalancheLib.deployAndSetupInfrastructure(address(platform));
        factory = Factory(address(platform.factory()));
    }

    function _deal(address token, address to, uint amount) internal virtual override {
        deal(token, to, amount);
    }
}
