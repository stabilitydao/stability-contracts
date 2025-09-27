// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PlasmaConstantsLib} from "./PlasmaConstantsLib.sol";
import {IPlatformDeployer} from "../../src/interfaces/IPlatformDeployer.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {StrategyDeveloperLib} from "../../src/strategies/libs/StrategyDeveloperLib.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";

library PlasmaLib {
    function platformDeployParams() internal pure returns (IPlatformDeployer.DeployPlatformParams memory p) {
        p.multisig = PlasmaConstantsLib.MULTISIG;
        p.version = "2025.09.1-alpha";
        p.targetExchangeAsset = PlasmaConstantsLib.TOKEN_USDT0;
        p.fee = 20_000;
    }

    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return ISwapper.AddPoolData({pool: pool, ammAdapterId: ammAdapterId, tokenIn: tokenIn, tokenOut: tokenOut});
    }

    function _addStrategyLogic(IFactory factory, string memory id, address implementation, bool farming) internal {
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: id,
                implementation: address(implementation),
                deployAllowed: true,
                upgradeAllowed: true,
                farming: farming,
                tokenId: type(uint).max
            }),
            StrategyDeveloperLib.getDeveloper(id)
        );
    }

    function testChainDeployLib() external {}

}