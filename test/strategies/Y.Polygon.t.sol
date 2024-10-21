// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";

contract YearnStrategyTest is PolygonSetup, UniversalTest {
    constructor() {
        vm.rollFork(55000000); // Mar-23-2024 07:56:52 PM +UTC
    }

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

    function _preDeposit() internal override {
        if (IStrategy(currentStrategy).underlying() == PolygonLib.YEARN_USDT) {
            // for some vault we need to cover deposit by underlying as first vault deposit
            address vault = IStrategy(currentStrategy).vault();
            address[] memory underlyingAssets = new address[](1);
            underlyingAssets[0] = PolygonLib.YEARN_USDT;
            uint[] memory underlyingAmounts = new uint[](1);
            underlyingAmounts[0] = 100e6;
            _deal(underlyingAssets[0], address(this), 100e6);
            IERC20(underlyingAssets[0]).approve(vault, type(uint).max);
            IVault(vault).depositAssets(underlyingAssets, underlyingAmounts, 0, address(0));

            // for some vault we setup ecosystem fee
            vm.startPrank(address(0));
            platform.setEcosystemRevenueReceiver(address(10));
            platform.setFees(6_000, 30_000, 30_000, 40_000);
            vm.stopPrank();
        }
    }
}
