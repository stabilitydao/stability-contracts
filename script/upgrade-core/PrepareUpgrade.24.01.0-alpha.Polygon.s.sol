// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {Factory} from "../../src/core/Factory.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {RVault} from "../../src/core/vaults/RVault.sol";
import {RMVault} from "../../src/core/vaults/RMVault.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";

contract PrepareUpgrade3Polygon is Script {
    address public constant PLATFORM = 0xb2a0737ef27b5Cc474D24c779af612159b1c3e60;
    string public constant ALGEBRA = "Algebra";
    string internal constant COMPOUNDING = "Compounding";
    string internal constant REWARDING = "Rewarding";
    string internal constant REWARDING_MANAGED = "Rewarding Managed";
    address public constant TOKEN_USDCe = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public constant TOKEN_USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address public constant TOKEN_dQUICK = 0x958d208Cdf087843e9AD98d23823d32E17d723A1;
    address public constant TOKEN_WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant POOL_QUICKSWAPV3_USDCe_USDC = 0xEecB5Db986c20a8C88D8332E7e252A9671565751;
    address public constant QUICKSWAP_POSITION_MANAGER = 0x8eF88E4c7CfbbaC1C163f7eddd4B578792201de6;
    address public constant QUICKSWAP_FARMING_CENTER = 0x7F281A8cdF66eF5e9db8434Ec6D97acc1bc01E78;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Factory 1.0.2: setVaultStatus updated
        new Factory();

        // Vaults 1.1.0: setName, setSymbol, gas optimization
        new CVault();
        new RVault();
        new RMVault();

        // route for native USDC
        ISwapper.AddPoolData[] memory pools = new ISwapper.AddPoolData[](1);
        pools[0] = ISwapper.AddPoolData({
            pool: POOL_QUICKSWAPV3_USDCe_USDC,
            ammAdapterId: ALGEBRA,
            tokenIn: TOKEN_USDC,
            tokenOut: TOKEN_USDCe
        });
        ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());
        swapper.addPools(pools, false);
        address[] memory tokenIn = new address[](1);
        tokenIn[0] = TOKEN_USDC;
        uint[] memory thresholdAmount = new uint[](1);
        thresholdAmount[0] = 1e3;
        swapper.setThresholds(tokenIn, thresholdAmount);

        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}
}
