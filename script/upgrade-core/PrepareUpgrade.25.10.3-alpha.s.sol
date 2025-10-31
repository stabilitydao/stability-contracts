// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Platform} from "../../src/core/Platform.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {XSTBL} from "../../src/tokenomics/XSTBL.sol";
import {StabilityDAO} from "../../src/tokenomics/StabilityDAO.sol";
import {IStabilityDAO} from "../../src/interfaces/IStabilityDAO.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {RevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";

contract PrepareUpgrade25103alpha is Script {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // XStaking 1.1.0
        new XStaking();

        // XSTBL 1.1.0
        new XSTBL();

        // Platform 1.6.2: IPlatform.stabilityDAO()
        new Platform();

        // RevenueRouter 1.7.1
        new RevenueRouter();

        // StabilityDAO
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new StabilityDAO()));
        StabilityDAO(address(proxy))
            .initialize(
                PLATFORM,
                SonicConstantsLib.TOKEN_XSTBL,
                SonicConstantsLib.XSTBL_XSTAKING,
                IStabilityDAO.DaoParams({
                    minimalPower: 4000e18,
                    exitPenalty: 50_00, // 50%, decimals 1e4
                    proposalThreshold: 10_000, // 10%
                    quorum: 30_000, // 30%
                    powerAllocationDelay: 1 days
                })
            );
        vm.stopBroadcast();
    }

    function testPrepareUpgrade() external {}
}
