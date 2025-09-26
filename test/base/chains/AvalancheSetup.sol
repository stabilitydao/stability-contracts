// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AvalancheLib} from "../../../chains/avalanche/AvalancheLib.sol";
import {AvalancheConstantsLib} from "../../../chains/avalanche/AvalancheConstantsLib.sol";
import {ChainSetup} from "../ChainSetup.sol";
import {DeployCore} from "../../../script/base/DeployCore.sol";
import {Factory} from "../../../src/core/Factory.sol";
import {Platform} from "../../../src/core/Platform.sol";
import {ISwapper} from "../../../src/interfaces/ISwapper.sol";
import {IPlatform} from "../../../src/interfaces/IPlatform.sol";

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
        address user = makeAddr("some external user");

        if (token == AvalancheConstantsLib.TOKEN_AUSD) {
            // deal doesn't work with AUSD
            // deal USDC instead and swap it to AUSD using platform's swapper
            deal(AvalancheConstantsLib.TOKEN_USDC, user, 2 * amount); // ASUD ~ USDC, so 2 * USDC is enough to get 1 ASUD in any case
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());

            vm.prank(user);
            IERC20(AvalancheConstantsLib.TOKEN_USDC).approve(address(swapper), type(uint).max);

            vm.prank(user);
            swapper.swap(AvalancheConstantsLib.TOKEN_USDC, AvalancheConstantsLib.TOKEN_AUSD, 2 * amount, 1_000); // 1%

            vm.prank(user);
            IERC20(AvalancheConstantsLib.TOKEN_AUSD).transfer(to, amount);
        } else {
            deal(token, to, amount);
        }
    }
}
