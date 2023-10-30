// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "../../../chains/PolygonLib.sol";
import "../ChainSetup.sol";
import "../../../src/core/Platform.sol";
import "../../../src/core/Factory.sol";
import "../../../src/core/CVault.sol";
import "../../../src/core/PriceReader.sol";
import "../../../src/core/Swapper.sol";
import "../../../src/core/VaultManager.sol";
import "../../../src/core/StrategyLogic.sol";
import "../../../src/core/proxy/Proxy.sol";
import "../../../src/core/AprOracle.sol";
import "../../../src/adapters/ChainlinkAdapter.sol";
import "../../../src/adapters/UniswapV3Adapter.sol";
import "../../../src/adapters/AlgebraAdapter.sol";
import "../../../src/adapters/KyberAdapter.sol";
import "../../../src/core/RVault.sol";
import "../../../script/libs/DeployLib.sol";
import "../../../script/libs/DeployAdapterLib.sol";
import "../../../script/Deploy.Polygon.s.sol";

abstract contract PolygonSetup is ChainSetup {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("POLYGON_RPC_URL")));
        vm.rollFork(48098000); // Sep-01-2023 03:23:25 PM +UTC
    }

    function testPolygonSetupStub() external {}

    function _init() internal override {
        //region ----- DeployPlatform -----
        platform = Platform(PolygonLib.runDeploy(false));
        factory = Factory(address(platform.factory()));
        //endregion -- DeployPlatform ----
    }
}
