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
    address public constant TOKEN_USDC = 0x391071Fe567d609E4af9d32de726d4C33679C7e2;
    address public constant TOKEN_stS = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;

    // Stable AMMs
    // Staked Sonic Symphony
    address public constant POOL_BEETHOVENX_wS_stS = 0x374641076B68371e69D03C417DAc3E5F236c32FA;
    //bytes32 public constant POOLID_BEETHOVENX_wS_stS = 0x374641076b68371e69d03c417dac3e5f236c32fa000000000000000000000006;

    // Beethoven X
    address public constant BEETHOVENX_BALANCER_HELPERS = 0x8E9aa87E45e92bad84D5F8DD1bff34Fb92637dE9;

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
        LogDeployLib.logDeployAmmAdapters(platform, showLog);
        //endregion ----- Deploy AMM adapters -----
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
