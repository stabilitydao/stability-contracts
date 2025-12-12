// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Script} from "forge-std/Script.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {DAO} from "../../src/tokenomics/DAO.sol";
import {XToken} from "../../src/tokenomics/XToken.sol";
import {RevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";

contract PrepareUpgrade25120alpha is Script {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // XStaking 1.1.2
        new XStaking();

        // DAO 1.1.0
        new DAO();

        // XToken 1.2.0
        new XToken();

        // RevenueRouter 1.8.0
        new RevenueRouter();

        vm.stopBroadcast();
    }

    function testPrepareUpgrade() external {}
}
