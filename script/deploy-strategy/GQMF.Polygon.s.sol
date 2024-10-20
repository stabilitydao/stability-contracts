// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/strategies/GammaQuickSwapMerklFarmStrategy.sol";
//import "../src/strategies/libs/ALMPositionNameLib.sol";
//import "../chains/PolygonLib.sol";

contract DeployStrategyGQMFPolygon is Script {
    address public constant PLATFORM = 0xb2a0737ef27b5Cc474D24c779af612159b1c3e60;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        new GammaQuickSwapMerklFarmStrategy();

        /*IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        IFactory.Farm[] memory _farms = new IFactory.Farm[](1);
        _farms[0] = _makeGammaQuickSwapMerklFarm(
            PolygonLib.TOKEN_dQUICK,
            PolygonLib.GAMMA_QUICKSWAP_USDCe_USDT,
            PolygonLib.GAMMA_QUICKSWAP_UNIPROXY,
            ALMPositionNameLib.STABLE
        );
        factory.addFarms(_farms);*/

        vm.stopBroadcast();
    }

    /*function _makeGammaQuickSwapMerklFarm(
        address rewardAsset0,
        address hypervisor,
        address uniProxy,
        uint preset
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IHypervisor(hypervisor).pool();
        farm.strategyLogicId = StrategyIdLib.GAMMA_QUICKSWAP_MERKL_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = rewardAsset0;
        farm.addresses = new address[](2);
        farm.addresses[0] = uniProxy;
        farm.addresses[1] = hypervisor;
        farm.nums = new uint[](1);
        farm.nums[0] = preset;
        farm.ticks = new int24[](0);
        return farm;
    }*/

    function testDeployPolygon() external {}
}
