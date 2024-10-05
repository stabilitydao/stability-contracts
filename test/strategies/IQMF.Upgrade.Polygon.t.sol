// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../../src/strategies/IchiQuickSwapMerklFarmStrategy.sol";
import "../../chains/PolygonLib.sol";
import "../../src/integrations/merkl/IMerklDistributor.sol";

contract IQMFUpgradeTest is Test {
    address public constant PLATFORM = 0xb2a0737ef27b5Cc474D24c779af612159b1c3e60;
    address public constant STRATEGY = 0x4753A6245CACf41187FEBFCb493a23784d859AcA; // IQMF

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("POLYGON_RPC_URL")));
        // vm.rollFork(56967000); // May-14-2024 05:36:03 PM +UTC
        vm.rollFork(62670000); // Oct-05-2024 04:41:36 PM +UTC
    }

    function testIQMFUpgrade() public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address multisig = IPlatform(PLATFORM).multisig();
        IHardWorker hw = IHardWorker(IPlatform(PLATFORM).hardWorker());

        vm.prank(multisig);
        hw.setDedicatedServerMsgSender(address(this), true);

        address[] memory vaultsForHardWork = new address[](1);
        vaultsForHardWork[0] = IStrategy(STRATEGY).vault();

        vm.expectRevert();
        hw.call(vaultsForHardWork);

        // deploy new impl and upgrade
        address strategyImplementation = address(new IchiQuickSwapMerklFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.ICHI_QUICKSWAP_MERKL_FARM,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(STRATEGY);

        assertGt(IERC20(PolygonLib.TOKEN_QUICK).balanceOf(STRATEGY), 0);
        assertEq(IFarmingStrategy(STRATEGY).farmingAssets()[0], PolygonLib.TOKEN_dQUICK);

        uint farmId = IFarmingStrategy(STRATEGY).farmId();
        address[] memory farmingAssets = new address[](2);
        farmingAssets[0] = PolygonLib.TOKEN_QUICK;
        farmingAssets[1] = PolygonLib.TOKEN_ICHI;
        address[] memory addresses = new address[](1);
        addresses[0] = PolygonLib.ICHI_QUICKSWAP_WETH_USDT;

        vm.startPrank(multisig);
        factory.updateFarm(
            farmId,
            IFactory.Farm({
                status: 0,
                pool: PolygonLib.POOL_QUICKSWAPV3_WETH_USDT,
                strategyLogicId: StrategyIdLib.ICHI_QUICKSWAP_MERKL_FARM,
                rewardAssets: farmingAssets,
                addresses: addresses,
                nums: new uint[](0),
                ticks: new int24[](0)
            })
        );
        IFarmingStrategy(STRATEGY).refreshFarmingAssets();
        vm.stopPrank();

        hw.call(vaultsForHardWork);

        assertEq(IERC20(PolygonLib.TOKEN_QUICK).balanceOf(STRATEGY), 0);
        assertEq(IFarmingStrategy(STRATEGY).farmingAssets()[0], PolygonLib.TOKEN_QUICK);
    }
}
