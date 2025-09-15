// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {IHardWorker} from "../../src/interfaces/IHardWorker.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IMerklStrategy} from "../../src/interfaces/IMerklStrategy.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IMerklDistributor} from "../../src/integrations/merkl/IMerklDistributor.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {IchiSwapXFarmStrategy} from "../../src/strategies/IchiSwapXFarmStrategy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";

contract ISFUpgrade3Test is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    // wS-stS stS
    address public constant STRATEGY = 0x289B9566238B26F6Abe1DB8E59AEB994F3F04984;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(19974000); // Apr-13-2025 12:32:47 PM +UTC
    }

    function testISFUpgrade3() public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address multisig = IPlatform(PLATFORM).multisig();
        IHardWorker hw = IHardWorker(IPlatform(PLATFORM).hardWorker());

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

        // update farm
        uint farmId = IFarmingStrategy(STRATEGY).farmId();
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = SonicConstantsLib.POOL_SWAPX_CL_WS_STS;
        farm.strategyLogicId = StrategyIdLib.SWAPX_FARM;
        farm.rewardAssets = new address[](2);
        farm.rewardAssets[0] = SonicConstantsLib.TOKEN_SWPX;
        farm.rewardAssets[1] = SonicConstantsLib.TOKEN_GEMSX;
        farm.addresses = new address[](2);
        farm.addresses[0] = SonicConstantsLib.ALM_ICHI_SWAPX_STS_WS;
        farm.addresses[1] = SonicConstantsLib.SWAPX_GAUGE_ICHI_STS_WS;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        vm.prank(multisig);
        factory.updateFarm(farmId, farm);

        // update farming assets
        vm.prank(multisig);
        IFarmingStrategy(STRATEGY).refreshFarmingAssets();

        // setup Merkl operator
        vm.prank(multisig);
        IMerklStrategy(STRATEGY).toggleDistributorUserOperator(SonicConstantsLib.MERKL_DISTRIBUTOR, address(this));

        // claim merkl
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint[] memory amounts = new uint[](1);
        bytes32[][] memory proofs = new bytes32[][](1);
        users[0] = STRATEGY;
        tokens[0] = SonicConstantsLib.TOKEN_GEMSX;
        amounts[0] = 1061308777230000000000;
        proofs[0] = new bytes32[](15);
        proofs[0][0] = 0xbac233cc596bedebda874a515b2764633f9a79e297ef6bb8e457a1637f068c03;
        proofs[0][1] = 0x86cc6897f0ceb466e1c5ff673c20053665121d98e6bfd2c51503a917b7e8f66f;
        proofs[0][2] = 0xfce0a5374dca149ac8ecccc9fe0b2f9abbd27158ff21bf164331d7544e0d5098;
        proofs[0][3] = 0x73af18000d45f429ab59d7d38d9574a106d9f6bdaddbfac85d0bbfb216c5ca7c;
        proofs[0][4] = 0xfbbef5569fa15e115de5c813878f49dd41f26f0a759ee7ec17470053aa83940a;
        proofs[0][5] = 0x922aaf49f13eb3fb3942d5e05f3ccdc95b7ccf0f59fca93842899a303554887e;
        proofs[0][6] = 0xba7f428e39ed548699000d76d58e3e51d02c21447aaa8aa0f139f864612e524d;
        proofs[0][7] = 0x1a497f6963103ef4d4474d849116b1e277f02e836847b9b9cbb8e366e3b715b6;
        proofs[0][8] = 0x4647c5437107930066caf498a65263fd809c9a6843ada6d2744daf5899018102;
        proofs[0][9] = 0xdf67ccbb07c800aa9a13da992b56f31b5174ed570878c457845d3c807d7c298e;
        proofs[0][10] = 0xf899b9e8c45c60fff522d43e85689451dabc53cf0d138530972ad54f22b2d21a;
        proofs[0][11] = 0xc378b6b38c1f6ea35b5592adbf7cc0b6bc724f548f969345860b756ebf975435;
        proofs[0][12] = 0x43b2ce0e099485b605a3e7282fd543c4a5d05c9e6c20829e6e51be5f9ff1854e;
        proofs[0][13] = 0x312bd2c8deb3d026fa4d40487ca0644602a5db35e8dba5e1befbee14f1b82a7f;
        proofs[0][14] = 0xfbe8c5036dd344946e82e9e90fae6f96567faa62f715bd47155dab2f7dbf4856;
        assertEq(IERC20(SonicConstantsLib.TOKEN_GEMSX).balanceOf(STRATEGY), 0);
        IMerklDistributor(SonicConstantsLib.MERKL_DISTRIBUTOR).claim(users, tokens, amounts, proofs);
        assertGt(IERC20(SonicConstantsLib.TOKEN_GEMSX).balanceOf(STRATEGY), 0);

        // route
        ISwapper.AddPoolData[] memory pools = new ISwapper.AddPoolData[](1);
        pools[0] = _makePoolData(
            SonicConstantsLib.POOL_SWAPX_CL_GEMSX_OS,
            AmmAdapterIdLib.ALGEBRA_V4,
            SonicConstantsLib.TOKEN_GEMSX,
            SonicConstantsLib.TOKEN_OS
        );
        ISwapper swapper = ISwapper(IPlatform(IControllable(STRATEGY).platform()).swapper());
        vm.prank(multisig);
        swapper.addPools(pools, false);

        // do HardWork
        vm.prank(multisig);
        hw.setDedicatedServerMsgSender(address(this), true);
        address[] memory vaultsForHardWork = new address[](1);
        vaultsForHardWork[0] = IStrategy(STRATEGY).vault();
        hw.call(vaultsForHardWork);
        assertEq(IERC20(SonicConstantsLib.TOKEN_GEMSX).balanceOf(STRATEGY), 0);

        //console.log(IStrategy(STRATEGY).lastApr()); // 159% APR
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
