// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {SiloManagedMerklFarmStrategy, CommonLib} from "../../src/strategies/SiloManagedMerklFarmStrategy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Factory} from "../../src/core/Factory.sol";
import {IProxy} from "../../src/interfaces/IProxy.sol";

contract SiMMFUpgradeTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public constant STRATEGY = 0xfa62bD9d148BB3B340AaabC0CD4B51a177ddF5AD;
    address public vault;

    uint private constant FORK_BLOCK = 47900000; // Sep-23-2025 12:01:57 PM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        vault = IStrategy(STRATEGY).vault();
        _upgradeFactory(); // upgrade to Factory v2.0.0
    }

    function testSiMMFUpgrade() public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address multisig = IPlatform(PLATFORM).multisig();

        // deploy new impl and upgrade
        address strategyImplementation = address(new SiloManagedMerklFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO_MANAGED_MERKL_FARM, strategyImplementation);
        factory.upgradeStrategyProxy(STRATEGY);

        (string memory specific,) = IStrategy(STRATEGY).getSpecificName();
        //console.log(specific);
        assertEq(CommonLib.eq(specific, "USDC 0x5b63..5775"), true);
        vm.expectRevert();
        IStrategy(STRATEGY).setSpecificName("Ma2");
        vm.prank(multisig);
        IStrategy(STRATEGY).setSpecificName("Ma2");
        (specific,) = IStrategy(STRATEGY).getSpecificName();
        assertEq(CommonLib.eq(specific, "Ma2"), true);

        assertEq(IStrategy(STRATEGY).protocols().length, 0);
        string[] memory protocols = new string[](2);
        protocols[0] = "org1:p1";
        protocols[1] = "org2:p2";
        vm.expectRevert();
        IStrategy(STRATEGY).setProtocols(protocols);
        vm.prank(multisig);
        IStrategy(STRATEGY).setProtocols(protocols);
        assertEq(IStrategy(STRATEGY).protocols().length, 2);
        assertEq(CommonLib.eq(IStrategy(STRATEGY).protocols()[1], "org2:p2"), true);
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
