// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console, Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IALM} from "../../src/interfaces/IALM.sol";
import {ALMShadowFarmStrategy} from "../../src/strategies/ALMShadowFarmStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IHardWorker} from "../../src/interfaces/IHardWorker.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {ILPStrategy} from "../../src/interfaces/ILPStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IUniswapV3Pool} from "../../src/integrations/uniswapv3/IUniswapV3Pool.sol";
import {RebalanceHelper} from "../../src/periphery/RebalanceHelper.sol";
import {Factory} from "../../src/core/Factory.sol";
import {IProxy} from "../../src/interfaces/IProxy.sol";

contract ASFUpgrade4Test is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STRATEGY = 0xa413658211DECDf44171ED6d8E37F7eDCD637117;
    uint public makePoolVolumePriceImpactTolerance = 200_000;
    address public vault;
    address public multisig;
    IFactory public factory;
    RebalanceHelper public rebalanceHelper;
    ISwapper public swapper;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(6420000); // Feb-03-2025 04:09:12 PM +UTC

        vault = IStrategy(STRATEGY).vault();
        multisig = IPlatform(PLATFORM).multisig();
        factory = IFactory(IPlatform(PLATFORM).factory());
        swapper = ISwapper(IPlatform(PLATFORM).swapper());
        rebalanceHelper = new RebalanceHelper();
        _upgradeFactory(); // upgrade to Factory v2.0.0
    }

    function getUniswapV3CurrentTick(address pool) public view returns (int24 tick) {
        //slither-disable-next-line unused-return
        (, tick,,,,,) = IUniswapV3Pool(pool).slot0();
    }

    function testDontNeedRebalance() public {
        // Prepare funds
        address[] memory assets = IStrategy(STRATEGY).assets();
        uint[] memory amounts = new uint[](2);
        amounts[0] = 1e18;
        amounts[1] = 1e6;

        deal(assets[0], address(this), amounts[0]);
        deal(assets[1], address(this), amounts[1]);
        IERC20(assets[0]).approve(vault, type(uint).max);
        IERC20(assets[1]).approve(vault, type(uint).max);

        // Upgrade strategy
        address newImpl = address(new ALMShadowFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.ALM_SHADOW_FARM, newImpl);
        factory.upgradeStrategyProxy(STRATEGY);
        // Deposit assets after upgrade
        IVault(vault).depositAssets(assets, amounts, 0, address(this));
        assertEq(IALM(STRATEGY).needRebalance(), false, "Strategy should not require rebalance");
    }

    function testBasePositionRebalance() public {
        // Prepare funds
        address[] memory assets = IStrategy(STRATEGY).assets();
        uint[] memory amounts = new uint[](2);
        amounts[0] = 1e18;
        amounts[1] = 1e6;

        deal(assets[0], address(this), amounts[0]);
        deal(assets[1], address(this), amounts[1]);
        IERC20(assets[0]).approve(vault, type(uint).max);
        IERC20(assets[1]).approve(vault, type(uint).max);

        IHardWorker hw = IHardWorker(IPlatform(PLATFORM).hardWorker());
        // Upgrade strategy
        address newImpl = address(new ALMShadowFarmStrategy());
        vm.prank(multisig);
        hw.setDedicatedServerMsgSender(address(this), true);
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.ALM_SHADOW_FARM, newImpl);
        factory.upgradeStrategyProxy(STRATEGY);
        address pool = ILPStrategy(STRATEGY).pool();
        address ammAdapter = address(ILPStrategy(STRATEGY).ammAdapter());
        // Deposit assets after upgrade
        IVault(vault).depositAssets(assets, amounts, 0, address(this));
        // Make volume to rebalance
        _swap(pool, ammAdapter, assets, 1e26); // tick is decreased

        // Rebalance
        if (IALM(STRATEGY).needRebalance()) {
            (bool[] memory burns, IALM.NewPosition[] memory mints) = rebalanceHelper.calcRebalanceArgs(STRATEGY, 10);
            IALM(STRATEGY).rebalance(burns, mints);
        } else {
            console.log("Strategy does not require rebalance");
            fail();
        }
        IALM.Position[] memory positions = IALM(STRATEGY).positions();
        assertEq(positions.length, 1, "Should be only base positions after rebalance");
    }

    function testLimitPositionRebalance() public {
        // Prepare funds
        address[] memory assets = IStrategy(STRATEGY).assets();
        uint[] memory amounts = new uint[](2);
        amounts[0] = 1e18;
        amounts[1] = 1e6;

        deal(assets[0], address(this), amounts[0]);
        deal(assets[1], address(this), amounts[1]);
        IERC20(assets[0]).approve(vault, type(uint).max);
        IERC20(assets[1]).approve(vault, type(uint).max);

        IHardWorker hw = IHardWorker(IPlatform(PLATFORM).hardWorker());
        // Upgrade strategy
        address newImpl = address(new ALMShadowFarmStrategy());
        vm.prank(multisig);
        hw.setDedicatedServerMsgSender(address(this), true);
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.ALM_SHADOW_FARM, newImpl);
        factory.upgradeStrategyProxy(STRATEGY);
        address pool = ILPStrategy(STRATEGY).pool();
        address ammAdapter = address(ILPStrategy(STRATEGY).ammAdapter());
        // Deposit assets after upgrade
        IVault(vault).depositAssets(assets, amounts, 0, address(this));
        // Make volume to rebalance
        _swap(pool, ammAdapter, assets, 1e25); // tick is decreased

        // Rebalance
        if (IALM(STRATEGY).needRebalance()) {
            (bool[] memory burns, IALM.NewPosition[] memory mints) = rebalanceHelper.calcRebalanceArgs(STRATEGY, 10);
            IALM(STRATEGY).rebalance(burns, mints);
        } else {
            console.log("Strategy does not require rebalance");
            fail();
        }
        IALM.Position[] memory positions = IALM(STRATEGY).positions();
        assertEq(positions.length, 2, "No limit positions after rebalance");
        // Make volume to another rebalance
        _swap(pool, ammAdapter, assets, 1e25);

        // Rebalance
        if (IALM(STRATEGY).needRebalance()) {
            (bool[] memory burns, IALM.NewPosition[] memory mints) = rebalanceHelper.calcRebalanceArgs(STRATEGY, 10);
            IALM(STRATEGY).rebalance(burns, mints);
        } else {
            console.log("Strategy does not require rebalance");
            fail();
        }
        IALM.Position[] memory positionsAfter = IALM(STRATEGY).positions();
        assertEq(positionsAfter.length, 2, "No limit positions after rebalance");
        assertNotEq(positions[1].tickUpper, positionsAfter[1].tickUpper, "Limit position is not rebalanced");
    }

    function _swap(address pool, address ammAdapter, address[] memory assets_, uint amount0) internal {
        ISwapper.PoolData[] memory poolData = new ISwapper.PoolData[](1);
        poolData[0].pool = pool;
        poolData[0].ammAdapter = ammAdapter;
        poolData[0].tokenIn = assets_[0];
        poolData[0].tokenOut = assets_[1];
        IERC20(assets_[0]).approve(address(swapper), amount0);
        // incrementing need for some tokens with custom fee
        deal(assets_[0], address(this), amount0 + 1);
        swapper.swapWithRoute(poolData, amount0, makePoolVolumePriceImpactTolerance);
    }

    function _upgradeFactory() internal {
        // deploy new Factory implementation
        address newImpl = address(new Factory());

        // get the proxy address for the factory
        address factoryProxy = address(IPlatform(PLATFORM).factory());

        // prank as the platform because only it can upgrade
        vm.prank(PLATFORM);
        IProxy(factoryProxy).upgrade(newImpl);

        // refresh the factory instance to point to the proxy (now using new impl)
        factory = IFactory(factoryProxy);
    }
}
