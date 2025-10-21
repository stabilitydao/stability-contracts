// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {UniswapV3Adapter} from "../../src/adapters/UniswapV3Adapter.sol";
import {AlgebraAdapter} from "../../src/adapters/AlgebraAdapter.sol";
import {KyberAdapter} from "../../src/adapters/KyberAdapter.sol";
import {CurveAdapter} from "../../src/adapters/CurveAdapter.sol";
import {BalancerComposableStableAdapter} from "../../src/adapters/BalancerComposableStableAdapter.sol";
import {BalancerWeightedAdapter} from "../../src/adapters/BalancerWeightedAdapter.sol";
import {SolidlyAdapter} from "../../src/adapters/SolidlyAdapter.sol";
import {AlgebraV4Adapter} from "../../src/adapters/AlgebraV4Adapter.sol";
import {ERC4626Adapter} from "../../src/adapters/ERC4626Adapter.sol";
import {BalancerV3StableAdapter} from "../../src/adapters/BalancerV3StableAdapter.sol";
import {PendleAdapter} from "../../src/adapters/PendleAdapter.sol";
import {MetaVaultAdapter} from "../../src/adapters/MetaVaultAdapter.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {BalancerV3ReClammAdapter} from "../../src/adapters/BalancerV3ReClammAdapter.sol";

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

        if (eq(id, AmmAdapterIdLib.SOLIDLY)) {
            proxy.initProxy(address(new SolidlyAdapter()));
        }

        if (eq(id, AmmAdapterIdLib.ALGEBRA_V4)) {
            proxy.initProxy(address(new AlgebraV4Adapter()));
        }

        if (eq(id, AmmAdapterIdLib.ERC_4626)) {
            proxy.initProxy(address(new ERC4626Adapter()));
        }

        if (eq(id, AmmAdapterIdLib.BALANCER_V3_STABLE)) {
            proxy.initProxy(address(new BalancerV3StableAdapter()));
        }

        if (eq(id, AmmAdapterIdLib.PENDLE)) {
            proxy.initProxy(address(new PendleAdapter()));
        }

        if (eq(id, AmmAdapterIdLib.META_VAULT)) {
            proxy.initProxy(address(new MetaVaultAdapter()));
        }

        if (eq(id, AmmAdapterIdLib.BALANCER_V3_RECLAMM)) {
            proxy.initProxy(address(new BalancerV3ReClammAdapter()));
        }

        require(proxy.implementation() != address(0), string.concat("Unknown AmmAdapter:", id));
        IAmmAdapter(address(proxy)).init(platform);
        IPlatform(platform).addAmmAdapter(id, address(proxy));

        return address(proxy);
    }

    function eq(string memory a, string memory b) public pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function testDeployAdapterLib() external {}
}
