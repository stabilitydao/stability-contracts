// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";
import "../../src/integrations/defiedge/IDefiEdgeStrategyFactory.sol";

contract DefiEdgeQuickSwapMerklFarmStrategyTest is PolygonSetup, UniversalTest {
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant USD = address(840);

    function testDQMF() public universalTest {
        // vm.rollFork(52400000); // Jan-16-2024 05:22:08 PM +UTC

        // change heartbeat to prevent "OLD_PRICE revert"
        IDefiEdgeStrategyFactory factory = IDefiEdgeStrategyFactory(0x730d158D29165C55aBF368e9608Af160DD21Bd80);
        address gov = factory.governance();
        vm.startPrank(gov);
        factory.setMinHeartbeat(PolygonLib.TOKEN_WETH, USD, 86400 * 365);
        factory.setMinHeartbeat(PolygonLib.TOKEN_WMATIC, USD, 86400 * 365);
        factory.setMinHeartbeat(PolygonLib.TOKEN_USDCe, USD, 86400 * 365);
        factory.setMinHeartbeat(PolygonLib.TOKEN_WETH, ETH, 86400 * 365);
        factory.setMinHeartbeat(PolygonLib.TOKEN_WMATIC, ETH, 86400 * 365);
        vm.stopPrank();

        // add farms for testing
        _addStrategy(18);
        _addStrategy(19);
        _addStrategy(20);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.DEFIEDGE_QUICKSWAP_MERKL_FARM,
                pool: address(0),
                farmId: farmId,
                underlying: address(0)
            })
        );
    }

    function _preHardWork() internal override {
        deal(PolygonLib.TOKEN_QUICK, currentStrategy, 10e18);
    }
}
