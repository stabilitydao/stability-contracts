// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/strategies/SteerQuickSwapMerklFarmStrategy.sol";
//import {StrategyDeveloperLib} from "../../src/strategies/libs/StrategyDeveloperLib.sol";

contract DeployStrategySQMFPolygon is Script {
    address public constant PLATFORM = 0xb2a0737ef27b5Cc474D24c779af612159b1c3e60;
    /*address public constant STEER_STRATEGY_WBTC_WETH_NARROW = 0x12a7b5510f8f5E13F75aFF4d00b2F88CC99d22DB;
    address public constant STEER_STRATEGY_USDC_WETH_NARROW = 0x7b99506C8E89D5ba835e00E2bC48e118264d44ff;
    address public constant STEER_STRATEGY_WMATIC_USDC_NARROW = 0x1EB20de00B0Ed23E3f9fDA7d23Fcbf473a23f180;
    address public constant STEER_STRATEGY_WMATIC_USDT_NARROW = 0x7dEFd09DCf1F2b0A17Da55011D22C9B7Cb3008ba;
    address public constant STEER_STRATEGY_WMATIC_USDT_NARROW_CHANNEL = 0x97915Dab9f8c0d6C32BEB598ceA3B44138C6c35E;
    address public constant STEER_STRATEGY_WMATIC_USDT_NARROW_ELASTIC = 0x94cdd4E4a461aD2108B761Cfa87D7Bc409d382e7;
    address public constant TOKEN_dQUICK = 0x958d208Cdf087843e9AD98d23823d32E17d723A1;
    address public constant TOKEN_WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;*/

    function run() external {
        //        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        //        IFactory.Farm[] memory farms = __farms();

        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        /*address implementation = address(*/
        new SteerQuickSwapMerklFarmStrategy(); /*)*/
        /*factory.addFarms(farms);
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
        );*/
        vm.stopBroadcast();
    }

    // steer quickswap
    /*function __farms() public view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](6);
        uint i;

        _farms[i++] = _makeSteerQuickSwapMerklFarm(STEER_STRATEGY_WMATIC_USDC_NARROW, ALMPositionNameLib.NARROW);
        _farms[i++] = _makeSteerQuickSwapMerklFarm(STEER_STRATEGY_WBTC_WETH_NARROW, ALMPositionNameLib.NARROW);
        _farms[i++] = _makeSteerQuickSwapMerklFarm(STEER_STRATEGY_USDC_WETH_NARROW, ALMPositionNameLib.NARROW);
        _farms[i++] = _makeSteerQuickSwapMerklFarm(STEER_STRATEGY_WMATIC_USDT_NARROW, ALMPositionNameLib.NARROW);
        _farms[i++] = _makeSteerQuickSwapMerklFarm(
            STEER_STRATEGY_WMATIC_USDT_NARROW_CHANNEL, ALMPositionNameLib.NARROW_VOLATILITY_CHANNEL
        );
        _farms[i++] =
            _makeSteerQuickSwapMerklFarm(STEER_STRATEGY_WMATIC_USDT_NARROW_ELASTIC, ALMPositionNameLib.NARROW_ELASTIC);
    }

    function _makeSteerQuickSwapMerklFarm(
        address hypervisor,
        uint preset
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IMultiPositionManager(hypervisor).pool();
        farm.strategyLogicId = StrategyIdLib.STEER_QUICKSWAP_MERKL_FARM;
        farm.rewardAssets = new address[](2);
        farm.rewardAssets[0] = TOKEN_dQUICK;
        farm.rewardAssets[1] = TOKEN_WMATIC;
        farm.addresses = new address[](1);
        farm.addresses[0] = hypervisor;
        farm.nums = new uint[](1);
        farm.nums[0] = preset;
        farm.ticks = new int24[](0);
        return farm;
    }*/

    function testDeployPolygon() external {}
}
