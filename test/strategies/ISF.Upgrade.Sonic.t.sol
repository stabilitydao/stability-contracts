// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHardWorker} from "../../src/interfaces/IHardWorker.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {IchiSwapXFarmStrategy} from "../../src/strategies/IchiSwapXFarmStrategy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Factory} from "../../src/core/Factory.sol";
import {IProxy} from "../../src/interfaces/IProxy.sol";

contract ISFUpgradeTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    // wS-USDC.e
    address public constant STRATEGY = 0x0f1Aa4EafAc9bc6C0D6fA474254f4d765cd35648;
    address public constant FEE_TREASURY = 0xDa9c8035aA67a8cf9BF5477e0D937F74566F9039;

    constructor() {
        // Mar-28-2025 09:09:20 PM +UTC
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 16646000));

        _upgradeFactory(); // upgrade to Factory v2.0.0
    }

    function testISFUpgrade() public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address multisig = IPlatform(PLATFORM).multisig();
        IHardWorker hw = IHardWorker(IPlatform(PLATFORM).hardWorker());

        vm.prank(multisig);
        hw.setDedicatedServerMsgSender(address(this), true);

        // deploy new impl and upgrade
        address strategyImplementation = address(new IchiSwapXFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.ICHI_SWAPX_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(STRATEGY);

        uint wsBalanceWas = IERC20(SonicConstantsLib.TOKEN_WS).balanceOf(FEE_TREASURY);
        uint stblBalanceWas = IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(IPlatform(PLATFORM).revenueRouter());

        address[] memory vaultsForHardWork = new address[](1);
        vaultsForHardWork[0] = IStrategy(STRATEGY).vault();
        /// forge-lint: disable-next-line
        hw.call(vaultsForHardWork);

        uint wsBalanceChange = IERC20(SonicConstantsLib.TOKEN_WS).balanceOf(FEE_TREASURY) - wsBalanceWas;
        uint stblBalanceChange =
            IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(IPlatform(PLATFORM).revenueRouter()) - stblBalanceWas;
        assertGt(wsBalanceChange, 0);
        assertGt(stblBalanceChange, 0);
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
