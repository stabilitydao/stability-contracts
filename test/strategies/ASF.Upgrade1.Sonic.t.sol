// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {ALMShadowFarmStrategy} from "../../src/strategies/ALMShadowFarmStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IALM} from "../../src/interfaces/IALM.sol";
import {IZap} from "../../src/interfaces/IZap.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";

contract ASFUpgrade1Test is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STRATEGY = 0xC37F16E3E5576496d06e3Bb2905f73574d59EAF7;
    address public vault;
    address public multisig;
    address public zap;
    IFactory public factory;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(6231000); // Feb-02-2025 09:55:27 AM +UTC
        vault = IStrategy(STRATEGY).vault();
        multisig = IPlatform(IControllable(STRATEGY).platform()).multisig();
        zap = IPlatform(IControllable(STRATEGY).platform()).zap();
        factory = IFactory(IPlatform(IControllable(STRATEGY).platform()).factory());
    }

    function testASFBugfix1() public {
        // check that depositAssets reverts and proportions are incorrect
        deal(SonicConstantsLib.TOKEN_wS, address(this), 10e18);
        deal(SonicConstantsLib.TOKEN_USDC, address(this), 10e6);
        IERC20(SonicConstantsLib.TOKEN_wS).approve(vault, type(uint).max);
        IERC20(SonicConstantsLib.TOKEN_USDC).approve(vault, type(uint).max);
        address[] memory assets = IStrategy(STRATEGY).assets();
        uint[] memory amounts = new uint[](2);
        amounts[0] = 10e18;
        amounts[1] = 10e6;
        vm.expectRevert();
        IVault(vault).depositAssets(assets, amounts, 0, address(this));
        uint[] memory proportions = IStrategy(STRATEGY).getAssetsProportions();
        //console.log(proportions[0], proportions[1]);
        assertLt(proportions[0], 7e17);

        // deploy new impl and upgrade
        address strategyImplementation = address(new ALMShadowFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.ALM_SHADOW_FARM,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );
        factory.upgradeStrategyProxy(STRATEGY);

        proportions = IStrategy(STRATEGY).getAssetsProportions();
        //console.log(proportions[0], proportions[1]);

        IVault(vault).depositAssets(assets, amounts, 0, address(this));
    }
}
