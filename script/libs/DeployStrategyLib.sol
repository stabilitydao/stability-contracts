// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../src/core/proxy/Proxy.sol";
import "../../src/interfaces/IPlatform.sol";
import "../../src/interfaces/IFactory.sol";
import "../../src/strategies/libs/StrategyIdLib.sol";
import "../../src/strategies/QuickswapV3StaticFarmStrategy.sol";
import "../../src/strategies/GammaQuickSwapMerklFarmStrategy.sol";
import "../../src/strategies/CompoundFarmStrategy.sol";
import "../../src/strategies/DefiEdgeQuickSwapMerklFarmStrategy.sol";
import "../../src/strategies/IchiQuickSwapMerklFarmStrategy.sol";
import "../../src/strategies/IchiRetroMerklFarmStrategy.sol";
import "../../src/strategies/libs/StrategyDeveloperLib.sol";

library DeployStrategyLib {
    function deployStrategy(
        address platform,
        string memory id,
        bool farming
    ) internal returns (address implementation) {
        IFactory factory = IFactory(IPlatform(platform).factory());
        implementation = factory.strategyLogicConfig(keccak256(bytes(id))).implementation;
        if (implementation != address(0)) {
            return implementation;
        }

        if (CommonLib.eq(id, StrategyIdLib.QUICKSWAPV3_STATIC_FARM)) {
            implementation = address(new QuickSwapV3StaticFarmStrategy());
        }

        if (CommonLib.eq(id, StrategyIdLib.GAMMA_QUICKSWAP_MERKL_FARM)) {
            implementation = address(new GammaQuickSwapMerklFarmStrategy());
        }

        if (CommonLib.eq(id, StrategyIdLib.COMPOUND_FARM)) {
            implementation = address(new CompoundFarmStrategy());
        }

        if (CommonLib.eq(id, StrategyIdLib.DEFIEDGE_QUICKSWAP_MERKL_FARM)) {
            implementation = address(new DefiEdgeQuickSwapMerklFarmStrategy());
        }

        if (CommonLib.eq(id, StrategyIdLib.ICHI_QUICKSWAP_MERKL_FARM)) {
            implementation = address(new IchiQuickSwapMerklFarmStrategy());
        }

        if (CommonLib.eq(id, StrategyIdLib.ICHI_RETRO_MERKL_FARM)) {
            implementation = address(new IchiRetroMerklFarmStrategy());
        }

        // nosemgrep
        require(implementation != address(0), "DeployStrategyLib: unknown strategy");

        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: id,
                implementation: implementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: farming,
                tokenId: type(uint).max
            }),
            StrategyDeveloperLib.getDeveloper(id)
        );
    }

    function testDeployStrategyLib() external {}
}
