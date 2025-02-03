// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SonicLib} from "../../chains/SonicLib.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {ILPStrategy} from "../../src/interfaces/ILPStrategy.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IALM} from "../../src/interfaces/IALM.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ALMLib} from "../../src/strategies/libs/ALMLib.sol";
import {RebalanceHelper} from "../../src/periphery/RebalanceHelper.sol";

contract ASFDebug2Test is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STRATEGY = 0xC37F16E3E5576496d06e3Bb2905f73574d59EAF7;
    address public constant HELPER_OLD = 0xF95C1E9fb9c7d357CAF969B741a2354630f7aEcD;
    address public vault;
    address public multisig;
    address public pool;

    RebalanceHelper public rebalancerHelper;
    RebalanceHelper public rebalancerHelperNew;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(6046000); // Jan-31-2025 05:36:45 PM +UTC
        vault = IStrategy(STRATEGY).vault();
        multisig = IPlatform(IControllable(STRATEGY).platform()).multisig();
        pool = ILPStrategy(STRATEGY).pool();
        rebalancerHelper = RebalanceHelper(HELPER_OLD);
        rebalancerHelperNew = new RebalanceHelper();
    }

    function testASRebalance1() public view {
        assertEq(IALM(STRATEGY).needRebalance(), true);

        /*int24 tick = ALMLib.getUniswapV3CurrentTick(pool);
        console.log("Tick:");
        console.logInt(tick);
        console.log("Current positions:");
        IALM.Position[] memory positions = IALM(STRATEGY).positions();
        console.logInt(positions[0].tickLower);
        console.logInt(positions[0].tickUpper);
        console.logInt(positions[1].tickLower);
        console.logInt(positions[1].tickUpper);

        (, IALM.NewPosition[] memory mintNewPositions) = rebalancerHelper.calcRebalanceArgs(STRATEGY, 100);
        console.log("Mint new positions:");
        console.logInt(mintNewPositions[0].tickLower);
        console.logInt(mintNewPositions[0].tickUpper);
        console.logInt(mintNewPositions[1].tickLower);
        console.logInt(mintNewPositions[1].tickUpper);

        (, mintNewPositions) = rebalancerHelperNew.calcRebalanceArgs(STRATEGY, 100);
        console.log("Mint new positions by new helper:");
        console.logInt(mintNewPositions[0].tickLower);
        console.logInt(mintNewPositions[0].tickUpper);
        console.logInt(mintNewPositions[1].tickLower);
        console.logInt(mintNewPositions[1].tickUpper);*/
    }
}
