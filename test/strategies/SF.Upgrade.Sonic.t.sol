// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {IHardWorker} from "../../src/interfaces/IHardWorker.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {SwapXFarmStrategy} from "../../src/strategies/SwapXFarmStrategy.sol";
import {Factory} from "../../src/core/Factory.sol";
import {IProxy} from "../../src/interfaces/IProxy.sol";

contract SFUpgradeTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STRATEGY = 0x90b226B729062A825d499B6828AC9573894E3cf4;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(3750000); // (Jan-13-2025 02:52:41 PM +UTC

        _upgradeFactory(); // upgrade to Factory v2.0.0
    }

    function testEFUpgrade() public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address multisig = IPlatform(PLATFORM).multisig();
        IHardWorker hw = IHardWorker(IPlatform(PLATFORM).hardWorker());

        vm.prank(multisig);
        hw.setDedicatedServerMsgSender(address(this), true);

        address[] memory vaultsForHardWork = new address[](1);
        vaultsForHardWork[0] = IStrategy(STRATEGY).vault();

        // test
        //deal(SonicConstantsLib.TOKEN_USDC, STRATEGY, 1700);
        ///////

        vm.expectRevert();
        /// forge-lint: disable-next-line
        hw.call(vaultsForHardWork);

        // deploy new impl and upgrade
        address strategyImplementation = address(new SwapXFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SWAPX_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(STRATEGY);

        vm.expectRevert();
        /// forge-lint: disable-next-line
        hw.call(vaultsForHardWork);

        vm.expectRevert();
        IStrategy(STRATEGY).setCustomPriceImpactTolerance(16_000);

        vm.prank(multisig);
        IStrategy(STRATEGY).setCustomPriceImpactTolerance(16_000);

        /// forge-lint: disable-next-line
        hw.call(vaultsForHardWork);
    }

    function _upgradeFactory() internal {
        // deploy new Factory implementation
        address newImpl = address(new Factory());

        // get the proxy address for the factory
        address factoryProxy = address(IPlatform(PLATFORM).factory());

        // prank as the platform because only it can upgrade
        vm.prank(PLATFORM);
        IProxy(factoryProxy).upgrade(newImpl);
    }
}
