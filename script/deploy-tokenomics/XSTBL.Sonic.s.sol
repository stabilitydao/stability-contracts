// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {XSTBL} from "../../src/tokenomics/XSTBL.sol";
import {RevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";
import {FeeTreasury} from "../../src/tokenomics/FeeTreasury.sol";

contract DeployXSTBLSystem is Script {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STBL = 0x78a76316F66224CBaCA6e70acB24D5ee5b2Bd2c7;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        Proxy xStakingProxy = new Proxy();
        xStakingProxy.initProxy(address(new XStaking()));
        Proxy xSTBLProxy = new Proxy();
        xSTBLProxy.initProxy(address(new XSTBL()));
        Proxy revenueRouterProxy = new Proxy();
        revenueRouterProxy.initProxy(address(new RevenueRouter()));
        Proxy feeTreasuryProxy = new Proxy();
        feeTreasuryProxy.initProxy(address(new FeeTreasury()));
        FeeTreasury(address(feeTreasuryProxy)).initialize(PLATFORM);
        XStaking(address(xStakingProxy)).initialize(PLATFORM, address(xSTBLProxy));
        XSTBL(address(xSTBLProxy)).initialize(PLATFORM, STBL, address(xStakingProxy), address(revenueRouterProxy));
        RevenueRouter(address(revenueRouterProxy)).initialize(PLATFORM, address(xSTBLProxy), address(feeTreasuryProxy));
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
