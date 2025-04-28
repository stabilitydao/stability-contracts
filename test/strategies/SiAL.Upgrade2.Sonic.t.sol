// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console, Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {SiloAdvancedLeverageStrategy} from "../../src/strategies/SiloAdvancedLeverageStrategy.sol";

/// @notice #245: Fix decreasing LTV on exits
contract SiALUpgrade2Test is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STRATEGY = 0x636364e3B21B17007E4e0b527F5C345c35064F16; // C-PT-aSonUSDC-14AUG2025-SAL

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(13624880); // Mar-14-2025 07:49:27 AM +UTC
    }

    function testSiALUpgrade() public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address multisig = IPlatform(PLATFORM).multisig();

        // deploy new impl and upgrade
        address strategyImplementation = address(new SiloAdvancedLeverageStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO_ADVANCED_LEVERAGE,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(STRATEGY);

        // todo

//        uint[] memory params = SiloAdvancedLeverageStrategy(payable(STRATEGY)).getUniversalParams();
//        //console.log(params[0]);
//        params[0] = 90_00;
//        vm.prank(multisig);
//        SiloAdvancedLeverageStrategy(payable(STRATEGY)).setUniversalParams(params);
//        params = SiloAdvancedLeverageStrategy(payable(STRATEGY)).getUniversalParams();
//        assertEq(params[0], 90_00);
    }
}
