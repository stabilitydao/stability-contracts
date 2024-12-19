// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../src/core/proxy/Proxy.sol";
import "../../src/adapters/libs/AmmAdapterIdLib.sol";
import "../../src/adapters/ChainlinkAdapter.sol";
import "../../src/adapters/UniswapV3Adapter.sol";
import "../../src/adapters/AlgebraAdapter.sol";
import "../../src/adapters/KyberAdapter.sol";
import "../../src/adapters/CurveAdapter.sol";
import {BalancerComposableStableAdapter} from "../../src/adapters/BalancerComposableStableAdapter.sol";
import {BalancerWeightedAdapter} from "../../src/adapters/BalancerWeightedAdapter.sol";

library DeployAdapterLib {
    function deployAmmAdapter(address platform, string memory id) internal returns (address) {
        address existAdapter = address(IPlatform(platform).ammAdapter(keccak256(bytes(id))).proxy);
        if (existAdapter != address(0)) {
            return existAdapter;
        }

        Proxy proxy = new Proxy();

        if (eq(id, AmmAdapterIdLib.UNISWAPV3)) {
            proxy.initProxy(address(new UniswapV3Adapter()));
        }

        if (eq(id, AmmAdapterIdLib.ALGEBRA)) {
            proxy.initProxy(address(new AlgebraAdapter()));
        }

        if (eq(id, AmmAdapterIdLib.KYBER)) {
            proxy.initProxy(address(new KyberAdapter()));
        }

        if (eq(id, AmmAdapterIdLib.CURVE)) {
            proxy.initProxy(address(new CurveAdapter()));
        }

        if (eq(id, AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE)) {
            proxy.initProxy(address(new BalancerComposableStableAdapter()));
        }

        if (eq(id, AmmAdapterIdLib.BALANCER_WEIGHTED)) {
            proxy.initProxy(address(new BalancerWeightedAdapter()));
        }

        require(proxy.implementation() != address(0), "Unknown AmmAdapter");
        IAmmAdapter(address(proxy)).init(platform);
        IPlatform(platform).addAmmAdapter(id, address(proxy));

        return address(proxy);
    }

    function eq(string memory a, string memory b) public pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function testDeployAdapterLib() external {}
}
