// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Platform} from "../../src/core/Platform.sol";
import "../../src/core/PriceReader.sol";
import "../../src/core/proxy/Proxy.sol";
import "../../src/test/MockERC20.sol";
import "../../src/test/MockERC721.sol";
import "../../src/core/VaultManager.sol";
import "../../src/core/StrategyLogic.sol";
import "../../src/core/vaults/CVault.sol";
import "../../src/core/vaults/RVault.sol";
import "../../src/core/vaults/RMVault.sol";

abstract contract MockSetup {
    Platform public platform;
    CVault public vaultImplementation;
    RVault public rVaultImplementation;
    RMVault public rmVaultImplementation;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockERC20 public tokenC;
    MockERC20 public tokenD;
    MockERC20 public tokenE;
    MockERC20 public lp;
    MockERC721 public builderPermitToken;
    MockERC20 public builderPayPerVaultToken;
    uint public builderPayPerVaultPrice;
    VaultManager public vaultManager;
    StrategyLogic public strategyLogic;

    constructor() {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new Platform()));
        platform = Platform(address(proxy));
        platform.initialize(address(this), "23.11.0-dev");
        vaultImplementation = new CVault();
        rVaultImplementation = new RVault();
        rmVaultImplementation = new RMVault();

        proxy = new Proxy();
        proxy.initProxy(address(new VaultManager()));
        vaultManager = VaultManager(address(proxy));
        vaultManager.init(address(platform));

        proxy = new Proxy();
        proxy.initProxy(address(new StrategyLogic()));
        strategyLogic = StrategyLogic(address(proxy));
        strategyLogic.init(address(platform));

        tokenA = new MockERC20();
        tokenA.init("Mock token A", "MOCKA", 18);
        tokenB = new MockERC20();
        tokenB.init("Mock token B", "MOCKB", 6);
        tokenC = new MockERC20();
        tokenC.init("Mock token C", "MOCKC", 6);
        tokenD = new MockERC20();
        tokenD.init("Mock token D", "MOCKD", 24);
        tokenE = new MockERC20();
        tokenE.init("Mock token E", "MOCKE", 24);
        lp = new MockERC20();
        lp.init("Mock LP", "MOCK_LP", 18);
        builderPermitToken = new MockERC721();
        builderPermitToken.init("Mock PM", "MOCK_PM");

        builderPayPerVaultToken = tokenC;
        builderPayPerVaultPrice = 10e6;
    }

    function testMockSetup() public {}
}
