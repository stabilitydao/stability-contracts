// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/strategies/GammaRetroMerklFarmStrategy.sol";

contract DeployStrategyGRMFPolygon is Script {
    address public constant PLATFORM = 0xb2a0737ef27b5Cc474D24c779af612159b1c3e60;
    //    address public constant GAMMA_RETRO_UNIPROXY = 0xDC8eE75f52FABF057ae43Bb4B85C55315b57186c;
    //    address public constant GAMMA_RETRO_WMATIC_USDCe_NARROW = 0xBE4E30b74b558E41f5837dC86562DF44aF57A013;
    //    address public constant GAMMA_RETRO_WMATIC_WETH_NARROW = 0xe7806B5ba13d4B2Ab3EaB3061cB31d4a4F3390Aa;
    //    address public constant GAMMA_RETRO_WBTC_WETH_WIDE = 0x336536F5bB478D8624dDcE0942fdeF5C92bC4662;
    //    address public constant TOKEN_oRETRO = 0x3A29CAb2E124919d14a6F735b6033a3AaD2B260F;

    function run() external {
        //        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        //        IFactory.Farm[] memory _farms = _farms6();

        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        new GammaRetroMerklFarmStrategy();

        //        factory.addFarms(_farms);

        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}

    /*// gamma retro
    function _farms6() internal view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](3);
        uint i;

        // [29]
        _farms[i++] = _makeGammaRetroMerklFarm(
            TOKEN_oRETRO, GAMMA_RETRO_WMATIC_USDCe_NARROW, GAMMA_RETRO_UNIPROXY, ALMPositionNameLib.NARROW
        );

        // [30]
        _farms[i++] = _makeGammaRetroMerklFarm(
            TOKEN_oRETRO, GAMMA_RETRO_WMATIC_WETH_NARROW, GAMMA_RETRO_UNIPROXY, ALMPositionNameLib.NARROW
        );

        // [31]
        _farms[i++] = _makeGammaRetroMerklFarm(
            TOKEN_oRETRO, GAMMA_RETRO_WBTC_WETH_WIDE, GAMMA_RETRO_UNIPROXY, ALMPositionNameLib.WIDE
        );
    }

    function _makeGammaRetroMerklFarm(
        address rewardAsset0,
        address hypervisor,
        address uniProxy,
        uint preset
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IHypervisor(hypervisor).pool();
        farm.strategyLogicId = StrategyIdLib.GAMMA_RETRO_MERKL_FARM;
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
}
