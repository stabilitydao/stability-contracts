// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {ALMShadowFarmStrategy} from "../../src/strategies/ALMShadowFarmStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IGaugeV3} from "../../src/integrations/shadow/IGaugeV3.sol";

contract ASFUpgrade3Test is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STRATEGY = 0xC37F16E3E5576496d06e3Bb2905f73574d59EAF7;
    address public constant NEW_GAUGE = 0xe879d0E44e6873cf4ab71686055a4f6817685f02;
    address public vault;
    address public multisig;
    IFactory public factory;
    ISwapper public swapper;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(14200000); // Mar-17-2025 07:27:00 AM +UTC
        vault = IStrategy(STRATEGY).vault();
        multisig = IPlatform(IControllable(STRATEGY).platform()).multisig();
        factory = IFactory(IPlatform(IControllable(STRATEGY).platform()).factory());
        swapper = ISwapper(IPlatform(IControllable(STRATEGY).platform()).swapper());
    }

    function testASFBugfix3() public {
        ISwapper.AddPoolData[] memory pools = new ISwapper.AddPoolData[](1);
        pools[0] = _makePoolData(
            SonicConstantsLib.POOL_SHADOW_CL_x33_SHADOW,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.TOKEN_x33,
            SonicConstantsLib.TOKEN_SHADOW
        );
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IGaugeV3(NEW_GAUGE).pool();
        farm.strategyLogicId = StrategyIdLib.ALM_SHADOW_FARM;
        farm.rewardAssets = IGaugeV3(NEW_GAUGE).getRewardTokens();
        farm.addresses = new address[](3);
        farm.addresses[0] = NEW_GAUGE;
        farm.addresses[1] = IGaugeV3(NEW_GAUGE).nfpManager();
        farm.addresses[2] = SonicConstantsLib.TOKEN_xSHADOW;
        farm.nums = new uint[](1);
        farm.nums[0] = 0;
        farm.ticks = new int24[](2);
        farm.ticks[0] = 1500;
        farm.ticks[1] = 600;
        vm.startPrank(multisig);
        factory.updateFarm(50, farm);
        IFarmingStrategy(STRATEGY).refreshFarmingAssets();
        swapper.addPools(pools, false);
        vm.stopPrank();

        address[] memory assets = IStrategy(STRATEGY).assets();
        uint[] memory amounts = new uint[](2);
        amounts[0] = 100e18;
        amounts[1] = 10e6;
        deal(assets[0], address(this), amounts[0]);
        deal(assets[1], address(this), amounts[1]);
        IERC20(assets[0]).approve(vault, type(uint).max);
        IERC20(assets[1]).approve(vault, type(uint).max);
        vm.expectRevert();
        IVault(vault).depositAssets(assets, amounts, 0, address(this));

        // deploy new impl and upgrade
        address strategyImplementation = address(new ALMShadowFarmStrategy());
        vm.startPrank(multisig);
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
        IFarmingStrategy(STRATEGY).refreshFarmingAssets();
        vm.stopPrank();

        IVault(vault).depositAssets(assets, amounts, 0, address(this));
    }

    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return ISwapper.AddPoolData({pool: pool, ammAdapterId: ammAdapterId, tokenIn: tokenIn, tokenOut: tokenOut});
    }
}
