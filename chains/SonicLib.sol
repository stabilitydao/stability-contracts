// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../script/libs/LogDeployLib.sol";
import {IPlatformDeployer} from "../src/interfaces/IPlatformDeployer.sol";
import {IBalancerAdapter} from "../src/interfaces/IBalancerAdapter.sol";
import {CommonLib} from "../src/core/libs/CommonLib.sol";
import {AmmAdapterIdLib} from "../src/adapters/libs/AmmAdapterIdLib.sol";
import {DeployAdapterLib} from "../script/libs/DeployAdapterLib.sol";

/// @dev Sonic network [chainId: 146] data library
//   _____             _
//  / ____|           (_)
// | (___   ___  _ __  _  ___
//  \___ \ / _ \| '_ \| |/ __|
//  ____) | (_) | | | | | (__
// |_____/ \___/|_| |_|_|\___|
//
/// @author Alien Deployer (https://github.com/a17)
library SonicLib {
    // initial addresses
    address public constant MULTISIG = 0xF564EBaC1182578398E94868bea1AbA6ba339652;

    // ERC20
    // https://docs.soniclabs.com/technology/contract-addresses
    address public constant TOKEN_wS = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
    address public constant TOKEN_wETH = 0x309C92261178fA0CF748A855e90Ae73FDb79EBc7;
    address public constant TOKEN_USDC = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address public constant TOKEN_stS = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;
    address public constant TOKEN_BEETS = 0x2D0E0814E62D80056181F5cd932274405966e4f0;
    address public constant TOKEN_EURC = 0xe715cbA7B5cCb33790ceBFF1436809d36cb17E57;

    // AMMs
    address public constant POOL_BEETHOVENX_wS_stS = 0x374641076B68371e69D03C417DAc3E5F236c32FA;
    address public constant POOL_BEETHOVENX_BEETS_stS = 0x10ac2F9DaE6539E77e372aDB14B1BF8fBD16b3e8;
    address public constant POOL_BEETHOVENX_wS_USDC = 0xf72883bE3a5D324Cf89DE2a6B22CB87098f1e948;

    // Beethoven X
    address public constant BEETHOVENX_BALANCER_HELPERS = 0x8E9aa87E45e92bad84D5F8DD1bff34Fb92637dE9;
    address public constant BEETHOVENX_GAUGE_wS_stS = 0x8476F3A8DA52092e7835167AFe27835dC171C133;

    //noinspection NoReturn
    function platformDeployParams() internal pure returns (IPlatformDeployer.DeployPlatformParams memory p) {
        p.multisig = MULTISIG;
        p.version = "24.06.0-alpha";
        p.buildingPermitToken = address(0);
        p.buildingPayPerVaultToken = TOKEN_wS;
        p.networkName = "Sonic";
        p.networkExtra = CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0xfec160), bytes3(0x000000)));
        p.targetExchangeAsset = TOKEN_wS;
        p.gelatoAutomate = address(0);
        p.gelatoMinBalance = 1e16;
        p.gelatoDepositAmount = 2e16;
    }

    function deployAndSetupInfrastructure(address platform, bool showLog) internal {
        IFactory factory = IFactory(IPlatform(platform).factory());

        //region ----- Deployed Platform -----
        if (showLog) {
            console.log("Deployed Stability platform", IPlatform(platform).platformVersion());
            console.log("Platform address: ", platform);
        }
        //endregion ----- Deployed Platform -----

        //region ----- Deploy and setup vault types -----
        _addVaultType(factory, VaultTypeLib.COMPOUNDING, address(new CVault()), 10e6);
        //endregion ----- Deploy and setup vault types -----

        // todo Deploy and setup oracle adapters

        //region ----- Deploy AMM adapters -----
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.UNISWAPV3);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE);
        IBalancerAdapter(
            IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE))).proxy
        ).setupHelpers(BEETHOVENX_BALANCER_HELPERS);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.BALANCER_WEIGHTED);
        IBalancerAdapter(IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.BALANCER_WEIGHTED))).proxy)
            .setupHelpers(BEETHOVENX_BALANCER_HELPERS);
        LogDeployLib.logDeployAmmAdapters(platform, showLog);
        //endregion ----- Deploy AMM adapters -----

        //region ----- Setup Swapper -----
        {
            (ISwapper.AddPoolData[] memory bcPools, ISwapper.AddPoolData[] memory pools) = routes();
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            swapper.addBlueChipsPools(bcPools, false);
            swapper.addPools(pools, false);
            address[] memory tokenIn = new address[](3);
            tokenIn[0] = TOKEN_wS;
            tokenIn[1] = TOKEN_stS;
            tokenIn[2] = TOKEN_BEETS;
            uint[] memory thresholdAmount = new uint[](3);
            thresholdAmount[0] = 1e10;
            thresholdAmount[1] = 1e10;
            thresholdAmount[2] = 1e10;
            swapper.setThresholds(tokenIn, thresholdAmount);
            LogDeployLib.logSetupSwapper(platform, showLog);
        }
        //endregion ----- Setup Swapper -----
    }

    function routes()
        public
        pure
        returns (ISwapper.AddPoolData[] memory bcPools, ISwapper.AddPoolData[] memory pools)
    {
        //region ----- BC pools ----
        bcPools = new ISwapper.AddPoolData[](2);
        bcPools[0] =
            _makePoolData(POOL_BEETHOVENX_wS_stS, AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE, TOKEN_stS, TOKEN_wS);
        bcPools[1] =
                        _makePoolData(POOL_BEETHOVENX_wS_USDC, AmmAdapterIdLib.BALANCER_WEIGHTED, TOKEN_USDC, TOKEN_wS);
        //endregion ----- BC pools ----

        //region ----- Pools ----
        pools = new ISwapper.AddPoolData[](4);
        uint i;
        pools[i++] =
            _makePoolData(POOL_BEETHOVENX_wS_stS, AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE, TOKEN_wS, TOKEN_stS);
        pools[i++] =
            _makePoolData(POOL_BEETHOVENX_wS_stS, AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE, TOKEN_stS, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_BEETHOVENX_BEETS_stS, AmmAdapterIdLib.BALANCER_WEIGHTED, TOKEN_BEETS, TOKEN_stS);
        pools[i++] = _makePoolData(POOL_BEETHOVENX_wS_USDC, AmmAdapterIdLib.BALANCER_WEIGHTED, TOKEN_USDC, TOKEN_wS);
        //endregion ----- Pools ----
    }

    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return ISwapper.AddPoolData({pool: pool, ammAdapterId: ammAdapterId, tokenIn: tokenIn, tokenOut: tokenOut});
    }

    function _addVaultType(IFactory factory, string memory id, address implementation, uint buildingPrice) internal {
        factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: id,
                implementation: implementation,
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: buildingPrice
            })
        );
    }

    function testChainLib() external {}
}
