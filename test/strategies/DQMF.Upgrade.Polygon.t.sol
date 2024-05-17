// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../../src/strategies/DefiEdgeQuickSwapMerklFarmStrategy.sol";
import "../../chains/PolygonLib.sol";
import "../../src/integrations/merkl/IMerklDistributor.sol";

contract DQMFUpgradeTest is Test {
    address public constant PLATFORM = 0xb2a0737ef27b5Cc474D24c779af612159b1c3e60;
    address public constant STRATEGY = 0xaA2746b88378Fc51e1dd3C3C79D5cb6a7095C98f;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("POLYGON_RPC_URL")));
        vm.rollFork(56967000); // May-14-2024 05:36:03 PM +UTC
    }

    function testDQMFUpgrade() public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address operator = IPlatform(PLATFORM).multisig();

        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint[] memory amounts = new uint[](1);
        bytes32[][] memory proofs = new bytes32[][](1);
        users[0] = 0xaA2746b88378Fc51e1dd3C3C79D5cb6a7095C98f;
        tokens[0] = 0x958d208Cdf087843e9AD98d23823d32E17d723A1;
        amounts[0] = 37103984491124500000000;
        proofs[0] = new bytes32[](16);
        proofs[0][0] = 0x5b58d42e0e181ef7f3b23032a5dbce04ffd5d60358fbb41d020c018ce59fa23a;
        proofs[0][1] = 0x76e47deb52c301f33fafb12975cbc6f3ef13b542ead6f93eee0c1593de75a2fb;
        proofs[0][2] = 0x662ff9a15b05a359a082a2375a9e826111a7df4dcb0940db4a3804d68da9c3c4;
        proofs[0][3] = 0x928549853077603facb65df41322f817e3d0a336d466086a7a476565171214b0;
        proofs[0][4] = 0x37417d86dbb0358449fa7e4c8746ee82dc8ad0041e643f320baef0715f22b39a;
        proofs[0][5] = 0xab0598cc1f5f71242a249ba8278f506ec8ec1ec617fc0798bda9f9edff65e538;
        proofs[0][6] = 0xaf7d55d1f1cc65c3fd977a8ba21d054074122e47bf7b773d8af209a345f539b5;
        proofs[0][7] = 0x048665f985491b473d20c421ea50a0ae6ce7178aa17d91e88e84a151b3c8b69a;
        proofs[0][8] = 0x7cd95c868b669a4f22f6d0993f912a929d6a96e14a570974f8d4af64865e6d0c;
        proofs[0][9] = 0x1cabce2d2d79a3675ceaf480d4ac28ecb1ebb24372909c7763136cc0c502608f;
        proofs[0][10] = 0x2ce618f043a5155ce69364a1db2661f54d7b99a79c6b027b0574de642b407794;
        proofs[0][11] = 0x335a185965b1f948f8352760310a93fbe59d89982c75652df25c7593e47d04cc;
        proofs[0][12] = 0x63e3c9d58777fb954d5d0e7ba3894947f1b0c930ad890b8bf140e7eb046c27ab;
        proofs[0][13] = 0xff351547defe76e50fbe6ac13eabf314a5a697cffa7ee53fdb927606476b1687;
        proofs[0][14] = 0x763bf3094b6c61d71e00399a61aa368f687aa1918a0fcf35b726455f32b09e4a;
        proofs[0][15] = 0x516a5717c304e641316ffeaf637fac0c9a80c4aaa7d07af8ec87cc44dceaff40;

        vm.expectRevert(abi.encodeWithSelector(IMerklDistributor.NotWhitelisted.selector));
        IMerklDistributor(PolygonLib.MERKL_DISTRIBUTOR).claim(users, tokens, amounts, proofs);

        // deploy new impl and upgrade
        address strategyImplementation = address(new DefiEdgeQuickSwapMerklFarmStrategy());
        vm.prank(operator);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.DEFIEDGE_QUICKSWAP_MERKL_FARM,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(STRATEGY);

        vm.prank(operator);
        IMerklStrategy(STRATEGY).toggleDistributorUserOperator(PolygonLib.MERKL_DISTRIBUTOR, address(this));

        IMerklDistributor(PolygonLib.MERKL_DISTRIBUTOR).claim(users, tokens, amounts, proofs);
    }
}
