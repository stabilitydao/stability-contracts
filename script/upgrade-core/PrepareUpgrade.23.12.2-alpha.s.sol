// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {AlgebraAdapter} from "../../src/adapters/AlgebraAdapter.sol";
import {UniswapV3Adapter} from "../../src/adapters/UniswapV3Adapter.sol";
import {KyberAdapter} from "../../src/adapters/KyberAdapter.sol";
import {Zap} from "../../src/core/Zap.sol";

contract PrepareUpgrade2 is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new AlgebraAdapter();
        new UniswapV3Adapter();
        new KyberAdapter();
        new Zap();
        vm.stopBroadcast();
    }

    function testPrepareUpgrade() external {}
}
