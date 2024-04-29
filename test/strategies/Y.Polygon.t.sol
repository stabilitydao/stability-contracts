// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";

contract YearnStrategyTest is PolygonSetup, UniversalTest {
    function testYearnStrategy() public universalTest {
        _addStrategy(PolygonLib.YEARN_USDCe);
        _addStrategy(PolygonLib.YEARN_DAI);
        _addStrategy(PolygonLib.YEARN_USDT);
        _addStrategy(PolygonLib.YEARN_WMATIC);
        _addStrategy(PolygonLib.YEARN_WETH);
    }

    function _addStrategy(address yaernV3Vault) internal {
        strategies.push(
            Strategy({id: StrategyIdLib.YEARN, pool: address(0), farmId: type(uint).max, underlying: yaernV3Vault})
        );
    }
}
