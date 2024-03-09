// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../../src/strategies/GammaRetroMerklFarmStrategy.sol";
import "../../chains/PolygonLib.sol";

contract GRMFUpgradeTest is Test {
    address public constant PLATFORM = 0xb2a0737ef27b5Cc474D24c779af612159b1c3e60;
    address public constant STRATEGY = 0x5a1961581a4daDd2eA8D2DE60783BD1417E74D8a;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("POLYGON_RPC_URL")));
        vm.rollFork(54449000); // Mar-09-2024
    }

    function testGRMFUpgrade() public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address operator = IPlatform(PLATFORM).multisig();
        IVault vault = IVault(IStrategy(STRATEGY).vault());
        ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());

        // add new swapper route
        ISwapper.AddPoolData[] memory pools = new ISwapper.AddPoolData[](1);
        pools[0] = ISwapper.AddPoolData({
            pool: PolygonLib.POOL_RETRO_USDCe_CASH_100,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: PolygonLib.TOKEN_CASH,
            tokenOut: PolygonLib.TOKEN_USDCe
        });
        vm.prank(operator);
        swapper.addPools(pools, false);

        // deploy new impl and upgrade
        address strategyImplementation = address(new GammaRetroMerklFarmStrategy());
        vm.prank(operator);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.GAMMA_RETRO_MERKL_FARM,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );
        factory.upgradeStrategyProxy(STRATEGY);

        // hardwork without initialization must revert
        deal(PolygonLib.TOKEN_oRETRO, STRATEGY, 10e18);
        vm.expectRevert("Init upgraded strategy first!");
        vm.prank(operator);
        vault.doHardWork();

        vm.prank(operator);
        GammaRetroMerklFarmStrategy(STRATEGY).upgradeStorageToVersion2(
            PolygonLib.TOKEN_CASH,
            PolygonLib.POOL_RETRO_USDCe_CASH_100,
            PolygonLib.POOL_RETRO_oRETRO_RETRO_10000,
            PolygonLib.POOL_RETRO_CASH_RETRO_10000,
            PolygonLib.RETRO_QUOTER
        );

        vm.prank(operator);
        vault.doHardWork();
    }
}
