// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DAO, IDAO} from "../../src/tokenomics/DAO.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {Script} from "forge-std/Script.sol";
import {StdConfig} from "forge-std/StdConfig.sol";

contract DeployDAO is Script {
    uint internal constant SONIC_CHAIN_ID = 146;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // ---------------------- Initialize
        StdConfig config = new StdConfig("./config.toml", false); // read only config
        StdConfig configDeployed = new StdConfig("./config.d.toml", true); // auto-write deployed addresses

        require(uint(configDeployed.get("xToken").ty.kind) != 0, "xToken is not deployed on the chain");
        require(uint(configDeployed.get("xStaking").ty.kind) != 0, "xStaking is not deployed on the chain");

        address xToken = configDeployed.get("xToken").toAddress();
        address xStaking = configDeployed.get("xStaking").toAddress();

        require(uint(config.get("PLATFORM").ty.kind) != 0, "Platform is not deployed on the chain");
        address platform = config.get("PLATFORM").toAddress();

        require(uint(configDeployed.get("DAO").ty.kind) == 0, "DAO is already deployed on the chain");

        IDAO.DaoParams memory params = IDAO.DaoParams({
            minimalPower: 4000000000000000000000,
            exitPenalty: 8000,
            proposalThreshold: 10000,
            quorum: 30000,
            powerAllocationDelay: 86400
        });

        // ---------------------- Deploy
        vm.startBroadcast(deployerPrivateKey);

        Proxy daoProxy = new Proxy();
        {
            address implementation = address(new DAO());
            daoProxy.initProxy(implementation);
            require(daoProxy.implementation() == implementation, "DAO: implementation mismatch");
        }

        DAO(address(daoProxy)).initialize(platform, xToken, address(xStaking), params, "Stability DAO", "STBL_DAO");

        // let's try to use Snapshot delegation
        // todo DAO(address(daoProxy)).setDelegationForbidden(true);

        // ---------------------- Write results
        vm.stopBroadcast();

        configDeployed.set("DAO", address(daoProxy));
    }

    function testDeployScript() external {}
}
