// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/strategies/SteerQuickSwapMerklFarmStrategy.sol";
import {StrategyDeveloperLib} from "../src/strategies/libs/StrategyDeveloperLib.sol";

contract DeployStrategySQMFPolygon is Script {
    address public constant PLATFORM = 0xb2a0737ef27b5Cc474D24c779af612159b1c3e60;
    address public constant STEER_STRATEGY_WMATIC_USDC = 0x280bE4533891E887F55847A773B93d043984Fbd5;
    address public constant STEER_STRATEGY_WBTC_WETH = 0x12a7b5510f8f5E13F75aFF4d00b2F88CC99d22DB;
    address public constant TOKEN_dQUICK = 0x958d208Cdf087843e9AD98d23823d32E17d723A1;

    function run() external {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        IFactory.Farm[] memory farms = __farms();

        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address implementation = address(new SteerQuickSwapMerklFarmStrategy());
        factory.addFarms(farms);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.STEER_QUICKSWAP_MERKL_FARM,
                implementation: implementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: type(uint).max
            }),
            StrategyDeveloperLib.getDeveloper(StrategyIdLib.STEER_QUICKSWAP_MERKL_FARM)
        );
        vm.stopBroadcast();
    }

    // steer quickswap
    function __farms() public view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](2);
        uint i;

        _farms[i++] = _makeSteerQuickSwapMerklFarm(
            STEER_STRATEGY_WMATIC_USDC,
            ALMPositionNameLib.NARROW
        );
        _farms[i++] = _makeSteerQuickSwapMerklFarm(
            STEER_STRATEGY_WBTC_WETH,
            ALMPositionNameLib.NARROW
        );
    }

    function _makeSteerQuickSwapMerklFarm(
        address hypervisor,
        uint preset
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IMultiPositionManager(hypervisor).pool();
        farm.strategyLogicId = StrategyIdLib.STEER_QUICKSWAP_MERKL_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = TOKEN_dQUICK;
        farm.addresses = new address[](1);
        farm.addresses[0] = hypervisor;
        farm.nums = new uint[](1);
        farm.nums[0] = preset;
        farm.ticks = new int24[](0);
        return farm;
    }

    function testDeployPolygon() external {}
}
