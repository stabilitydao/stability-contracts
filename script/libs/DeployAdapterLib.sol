// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "../../src/core/proxy/Proxy.sol";
import "../../src/adapters/libs/DexAdapterIdLib.sol";
import "../../src/adapters/ChainlinkAdapter.sol";
import "../../src/adapters/UniswapV3Adapter.sol";
import "../../src/adapters/AlgebraAdapter.sol";
import "../../src/adapters/KyberAdapter.sol";

library DeployAdapterLib {
    function deployDexAdapter(address platform, string memory id) internal returns (address) {
        address existAdapter = address(IPlatform(platform).dexAdapter(keccak256(bytes (id))).proxy);
        if (existAdapter != address(0)) {
            return existAdapter;
        }

        Proxy proxy = new Proxy();

        if (eq(id, DexAdapterIdLib.UNISWAPV3)) {
            proxy.initProxy(address(new UniswapV3Adapter()));
        }

        if (eq(id, DexAdapterIdLib.ALGEBRA)) {
            proxy.initProxy(address(new AlgebraAdapter()));
        }

        if (eq(id, DexAdapterIdLib.KYBER)) {
            proxy.initProxy(address(new KyberAdapter()));
        }

        require(proxy.implementation() != address(0), "Unknown DexAdapter");
        IDexAdapter(address(proxy)).init(platform);
        IPlatform(platform).addDexAdapter(id, address(proxy));

        return address(proxy);
    }

    function eq(string memory a, string memory b) public pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function testDeployAdapterLib() external {}
}
