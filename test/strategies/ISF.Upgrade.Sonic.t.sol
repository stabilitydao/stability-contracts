// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHardWorker} from "../../src/interfaces/IHardWorker.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {IchiSwapXFarmStrategy} from "../../src/strategies/IchiSwapXFarmStrategy.sol";
import {SonicLib} from "../../chains/SonicLib.sol";

contract ISFUpgradeTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    // wS-USDC.e
    address public constant STRATEGY = 0x0f1Aa4EafAc9bc6C0D6fA474254f4d765cd35648;
    address public constant FEE_TREASURY = 0xDa9c8035aA67a8cf9BF5477e0D937F74566F9039;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(16646000); // Mar-28-2025 09:09:20 PM +UTC
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
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.ICHI_SWAPX_FARM,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(STRATEGY);

        uint wsBalanceWas = IERC20(SonicLib.TOKEN_wS).balanceOf(FEE_TREASURY);
        uint stblBalanceWas = IERC20(SonicLib.TOKEN_STBL).balanceOf(IPlatform(PLATFORM).revenueRouter());

        address[] memory vaultsForHardWork = new address[](1);
        vaultsForHardWork[0] = IStrategy(STRATEGY).vault();
        hw.call(vaultsForHardWork);

        uint wsBalanceChange = IERC20(SonicLib.TOKEN_wS).balanceOf(FEE_TREASURY) - wsBalanceWas;
        uint stblBalanceChange =
            IERC20(SonicLib.TOKEN_STBL).balanceOf(IPlatform(PLATFORM).revenueRouter()) - stblBalanceWas;
        assertGt(wsBalanceChange, 0);
        assertGt(stblBalanceChange, 0);
    }
}
