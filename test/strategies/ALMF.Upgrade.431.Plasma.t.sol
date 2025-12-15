// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AaveLeverageMerklFarmStrategy} from "../../src/strategies/AaveLeverageMerklFarmStrategy.sol";
import {Test} from "forge-std/Test.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";

contract ALMFStrategyUpdate431PlasmaTest is Test {
    uint internal constant FORK_BLOCK = 7733125; // Dec-2-2025 08:23:16 UTC
    IFactory internal factory;

    /// @notice weeth-usdt x2
    address public constant ALMF_STRATEGY = 0x711119916bdF5edD4244b2d0462a0CEf16D2411f;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("PLASMA_RPC_URL"), FORK_BLOCK));
        factory = IFactory(IPlatform(PlasmaConstantsLib.PLATFORM).factory());
    }

    /// @notice Coverage: ensure that exchange asset index is updated inside _beforeHardwork
    function testHardworkAfterUpdate() public {
        _upgradeStrategy();

        // emulate Merkl rewards
        deal(PlasmaConstantsLib.TOKEN_WXPL, ALMF_STRATEGY, 1e18);
        skip(1 days);

        address vault = IStrategy(ALMF_STRATEGY).vault();

        uint totalBefore = IStrategy(ALMF_STRATEGY).total();

        vm.prank(address(vault));
        IStrategy(ALMF_STRATEGY).doHardWork();

        uint totalAfter = IStrategy(ALMF_STRATEGY).total();
        assertGt(totalAfter, totalBefore, "total after hardwork should be greater than before");
    }

    function _upgradeStrategy() internal {
        address strategyImplementation = address(new AaveLeverageMerklFarmStrategy());

        vm.prank(PlasmaConstantsLib.MULTISIG);
        factory.setStrategyImplementation(StrategyIdLib.AAVE_LEVERAGE_MERKL_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(address(ALMF_STRATEGY));
    }
}
