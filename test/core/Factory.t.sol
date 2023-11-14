// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console, Vm} from "forge-std/Test.sol";
import "../../src/core/Factory.sol";
import "../../src/core/vaults/CVault.sol";
import "../../src/strategies/libs/StrategyIdLib.sol";
import "../../src/core/proxy/Proxy.sol";
import "../../src/test/MockStrategy.sol";
import "../../src/test/MockAmmAdapter.sol";
import "../../src/test/MockStrategyUpgrade.sol";
import "../../src/test/MockVaultUpgrade.sol";
import "../../src/test/MockERC721.sol";
import "../base/MockSetup.sol";
import "../../src/interfaces/IStrategyLogic.sol";

contract FactoryTest is Test, MockSetup {
    Factory public factory;
    MockStrategy public strategyImplementation;
    MockAmmAdapter public ammAdapter;

    function setUp() public {
        Factory implementation = new Factory();
        Proxy proxy = new Proxy();
        proxy.initProxy(address(implementation));
        factory = Factory(address(proxy));
        factory.initialize(address(platform));
        strategyImplementation = new MockStrategy();

        ammAdapter = new MockAmmAdapter(address(tokenA), address(tokenB));

        platform.setup(
            IPlatform.SetupAddresses({
                factory: address(factory),
                priceReader: address(0),
                swapper: address(1),
                buildingPermitToken: address(builderPermitToken),
                buildingPayPerVaultToken: address(builderPayPerVaultToken),
                vaultManager: address(vaultManager),
                strategyLogic: address(strategyLogic),
                aprOracle: address(10),
                targetExchangeAsset: address(tokenA),
                hardWorker: address(0),
                zap: address(0)
            }),
            IPlatform.PlatformSettings({
                networkName: 'Localhost Ethereum',
                networkExtra: CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x7746d7), bytes3(0x040206))),
                fee: 6_000,
                feeShareVaultManager: 30_000,
                feeShareStrategyLogic: 30_000,
                feeShareEcosystem: 0,
                minInitialBoostPerDay: 30e18, // $30
                minInitialBoostDuration: 30 * 86400 // 30 days
            })
        );

        platform.addAmmAdapter('MOCKSWAP', address(ammAdapter));
    }

    function testInitialize() public {
        Factory implementation = new Factory();
        Proxy proxy = new Proxy();
        proxy.initProxy(address(implementation));
        Factory factory2 = Factory(address(proxy));

        factory2.initialize(address(platform));
    }

    function testDeployVaultAndStrategy() public {
        address[] memory addresses = new address[](3);
        uint[] memory nums = new uint[](0);
        int24[] memory ticks = new int24[](0);


        vm.expectRevert(abi.encodeWithSelector(IFactory.VaultImplementationIsNotAvailable.selector));
        factory.deployVaultAndStrategy(VaultTypeLib.COMPOUNDING, StrategyIdLib.DEV, new address[](0), new uint[](0), addresses, nums, ticks);

        factory.setVaultConfig(IFactory.VaultConfig({
            vaultType: VaultTypeLib.COMPOUNDING,
            implementation: address(vaultImplementation),
            deployAllowed: true,
            upgradeAllowed: true,
            buildingPrice: builderPayPerVaultPrice
        }));

        (,address impl, bool deployAllowed, bool upgradeAllowed,) = factory.vaultConfig(keccak256(abi.encodePacked(VaultTypeLib.COMPOUNDING)));
        assertEq(impl, address(vaultImplementation));
        assertEq(deployAllowed, true);
        assertEq(upgradeAllowed, true);

        vm.expectRevert(abi.encodeWithSelector(IFactory.StrategyImplementationIsNotAvailable.selector));
        factory.deployVaultAndStrategy(VaultTypeLib.COMPOUNDING, StrategyIdLib.DEV, new address[](0), new uint[](0), addresses, nums, ticks);

        factory.setStrategyLogicConfig(IFactory.StrategyLogicConfig({
            id: StrategyIdLib.DEV,
            implementation: address(strategyImplementation),
            deployAllowed: true,
            upgradeAllowed: true,
            farming: false,
            tokenId: type(uint).max
        }), address(this));
        (,,,,,uint strategyLogicTokenId) = factory.strategyLogicConfig(keccak256(bytes(StrategyIdLib.DEV)));
        bytes32[] memory hashes = factory.strategyLogicIdHashes();
        assertEq(hashes.length, 1);
        assertEq(strategyLogic.ownerOf(strategyLogicTokenId), address(this));

        uint userBalance = builderPayPerVaultToken.balanceOf(address(this));
        address payToken = platform.buildingPayPerVaultToken();
        vm.expectRevert(abi.encodeWithSelector(IFactory.YouDontHaveEnoughTokens.selector, userBalance, builderPayPerVaultPrice, payToken));
        factory.deployVaultAndStrategy(VaultTypeLib.COMPOUNDING, StrategyIdLib.DEV, new address[](0), new uint[](0), addresses, nums, ticks);

        builderPayPerVaultToken.mint(builderPayPerVaultPrice);
        builderPayPerVaultToken.approve(address(factory), builderPayPerVaultPrice);

        factory.setVaultConfig(IFactory.VaultConfig({
            vaultType: "TestVaultType",
            implementation: address(vaultImplementation),
            deployAllowed: false,
            upgradeAllowed: true,
            buildingPrice: 100
        }));

        vm.expectRevert(abi.encodeWithSelector(IFactory.VaultNotAllowedToDeploy.selector));
        factory.deployVaultAndStrategy("TestVaultType", StrategyIdLib.DEV, new address[](0), new uint[](0), addresses, nums, ticks);

        factory.setStrategyLogicConfig(IFactory.StrategyLogicConfig({
            id: StrategyIdLib.DEV,
            implementation: address(strategyImplementation),
            deployAllowed: false,
            upgradeAllowed: true,
            farming: false,
            tokenId: type(uint).max
        }), address(this));


        factory.setVaultConfig(IFactory.VaultConfig({
            vaultType: "TestVaultType",
            implementation: address(vaultImplementation),
            deployAllowed: true,
            upgradeAllowed: true,
            buildingPrice: 100
        }));

        vm.expectRevert(abi.encodeWithSelector(IFactory.StrategyLogicNotAllowedToDeploy.selector));
        factory.deployVaultAndStrategy("TestVaultType", StrategyIdLib.DEV, new address[](0), new uint[](0), addresses, nums, ticks);

        factory.setStrategyLogicConfig(IFactory.StrategyLogicConfig({
            id: StrategyIdLib.DEV,
            implementation: address(strategyImplementation),
            deployAllowed: true,
            upgradeAllowed: true,
            farming: false,
            tokenId: type(uint).max
        }), address(this));

        vm.expectRevert(bytes("Strategy: underlying token cant be zero for this strategy"));
        factory.deployVaultAndStrategy(VaultTypeLib.COMPOUNDING, StrategyIdLib.DEV, new address[](0), new uint[](0), addresses, nums, ticks);

        addresses[1] = address(1);
        addresses[2] = address(tokenA);

        vm.recordLogs();

        factory.deployVaultAndStrategy(VaultTypeLib.COMPOUNDING, StrategyIdLib.DEV, new address[](0), new uint[](0), addresses, nums, ticks);

        address vault;
        address strategy;
        bytes32 deploymentKey;
        uint tokenId;
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint i; i < entries.length; ++i) {
            if (entries[i].topics[0] == keccak256("VaultAndStrategy(address,string,string,address,address,string,string,address[],bytes32,uint256)")) {
                assertEq(address(uint160(uint(entries[i].topics[1]))), address(this));
                string memory vaultType;
                string memory strategyId;
                (vaultType, strategyId, vault, strategy,,,,deploymentKey,  tokenId) = abi.decode(entries[i].data, (string,string,address,address,string,string,address[],bytes32,uint));
                assertEq(vaultType, VaultTypeLib.COMPOUNDING);
                assertEq(strategyId, StrategyIdLib.DEV);
            }
        }
        assertEq(IERC20Metadata(vault).name(), "Stability MOCKA-MOCKB Dev Alpha DeepSpaceSwap Farm Good Params");

        assertEq(IERC20Metadata(vault).symbol(), "C-MOCKAMOCKB-DADFGP");

        assertEq(address(ILPStrategy(strategy).ammAdapter()), address(ammAdapter));
        assertEq(address(IStrategy(strategy).vault()), vault);
        assertEq(address(IStrategy(strategy).underlying()), address(1));
        assertEq(IStrategyProxy(strategy).STRATEGY_IMPLEMENTATION_LOGIC_ID_HASH(), keccak256(abi.encodePacked(StrategyIdLib.DEV)));
        assertEq(factory.deployedVaultsLength(), 1);
        assertEq(factory.deploymentKey(deploymentKey), vault);
        assertEq(factory.deployedVault(0), vault);
        address[] memory deployedVaults = factory.deployedVaults();
        assertEq(deployedVaults[0], vault);
        factory.VERSION();
        assertEq(vaultManager.balanceOf(address(this)), 1);
        assertEq(vaultManager.ownerOf(0), (address(this)));

        
    }

    function testUpgradeVault() public {
        MockVaultUpgrade newVaultImplementation = new MockVaultUpgrade();

        address[] memory addresses = new address[](3);
        addresses[1] = address(1);
        addresses[2] = address(tokenA);
        uint[] memory nums = new uint[](0);
        int24[] memory ticks = new int24[](0);

        factory.setVaultConfig(IFactory.VaultConfig({
            vaultType: VaultTypeLib.COMPOUNDING,
            implementation: address(vaultImplementation),
            deployAllowed: true,
            upgradeAllowed: true,
            buildingPrice: builderPayPerVaultPrice
        }));

        factory.setStrategyLogicConfig(IFactory.StrategyLogicConfig({
            id: StrategyIdLib.DEV,
            implementation: address(strategyImplementation),
            deployAllowed: true,
            upgradeAllowed: true,
            farming: false,
            tokenId: type(uint).max
        }), address(this));

        builderPermitToken.mint();
        (address vault,) = factory.deployVaultAndStrategy(VaultTypeLib.COMPOUNDING, StrategyIdLib.DEV, new address[](0), new uint[](0), addresses, nums, ticks);

        bytes32 vaultTypeHash = IVaultProxy(vault).VAULT_TYPE_HASH();
        vm.expectRevert(abi.encodeWithSelector(IFactory.AlreadyLastVersion.selector, vaultTypeHash));
        factory.upgradeVaultProxy(vault);

        factory.setVaultStatus(vault, 0);
        vm.expectRevert(abi.encodeWithSelector(IFactory.NotActiveVault.selector));
        factory.upgradeVaultProxy(vault);
        factory.setVaultStatus(vault, 1);

        factory.setVaultConfig(IFactory.VaultConfig({
            vaultType: VaultTypeLib.COMPOUNDING,
            implementation: address(newVaultImplementation),
            deployAllowed: true,
            upgradeAllowed: false,
            buildingPrice: builderPayPerVaultPrice
        }));

        vaultTypeHash = IVaultProxy(vault).VAULT_TYPE_HASH();
        vm.expectRevert(abi.encodeWithSelector(IFactory.UpgradeDenied.selector, vaultTypeHash));
        factory.upgradeVaultProxy(vault);

        factory.setVaultConfig(IFactory.VaultConfig({
            vaultType: VaultTypeLib.COMPOUNDING,
            implementation: address(newVaultImplementation),
            deployAllowed: true,
            upgradeAllowed: true,
            buildingPrice: builderPayPerVaultPrice
        }));

        factory.upgradeVaultProxy(vault);
    }

    function testUpgradeStrategy() public {
        MockStrategyUpgrade newStrategyImplementation = new MockStrategyUpgrade();

        address[] memory addresses = new address[](3);
        addresses[1] = address(1);
        addresses[2] = address(tokenA);
        uint[] memory nums = new uint[](0);
        int24[] memory ticks = new int24[](0);

        factory.setVaultConfig(IFactory.VaultConfig({
            vaultType: VaultTypeLib.COMPOUNDING,
            implementation: address(vaultImplementation),
            deployAllowed: true,
            upgradeAllowed: true,
            buildingPrice: builderPayPerVaultPrice
        }));

        factory.setStrategyLogicConfig(IFactory.StrategyLogicConfig({
            id: StrategyIdLib.DEV,
            implementation: address(strategyImplementation),
            deployAllowed: true,
            upgradeAllowed: true,
            farming: false,
            tokenId: type(uint).max
        }), address(this));

        builderPermitToken.mint();
        (, address strategy) = factory.deployVaultAndStrategy(VaultTypeLib.COMPOUNDING, StrategyIdLib.DEV, new address[](0), new uint[](0), addresses, nums, ticks);

        bytes32 strategyProxyHash = IStrategyProxy(strategy).STRATEGY_IMPLEMENTATION_LOGIC_ID_HASH();
        vm.expectRevert(abi.encodeWithSelector(IFactory.AlreadyLastVersion.selector, strategyProxyHash));
        factory.upgradeStrategyProxy(strategy);

        vm.expectRevert(abi.encodeWithSelector(IFactory.NotStrategy.selector));
        factory.upgradeStrategyProxy(address(1));

        {
        //vaultTypes()
        (
            string[] memory vaultType_,
            ,
            bool[] memory deployAllowed_,
            bool[] memory upgradeAllowed_,
            uint[] memory buildingPrice_,
            bytes32[] memory extra_
        ) = factory.vaultTypes();
        assertEq(vaultType_[0], VaultTypeLib.COMPOUNDING);
        assertEq(deployAllowed_[0], true);
        assertEq(upgradeAllowed_[0], true);
        assertEq(buildingPrice_[0], builderPayPerVaultPrice);
        assertFalse(extra_[0] == bytes32(0));

        //strategies()
        (
        string[] memory id_,
        bool[] memory deployAllowed__,
        bool[] memory upgradeAllowed__,
        bool[] memory farming_,
        uint[] memory tokenId_,
        string[] memory tokenURI_,
        bytes32[] memory extra__
        ) = factory.strategies();

        IStrategyLogic strategyLogicNft = IStrategyLogic(platform.strategyLogic());
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotExist.selector));
        strategyLogicNft.tokenURI(666);
        string memory tokenURI__ = strategyLogicNft.tokenURI(tokenId_[0]);
        assertEq(id_[0], StrategyIdLib.DEV);
        assertEq(deployAllowed__[0], true);
        assertEq(upgradeAllowed__[0], true);
        assertEq(farming_[0], false);
        assertEq(tokenId_[0], 0);
        assertEq(keccak256(abi.encodePacked(tokenURI_[0])), keccak256(abi.encodePacked(tokenURI__)));
        assertFalse(extra__[0] == bytes32(0)); 
        }

        factory.setStrategyLogicConfig(IFactory.StrategyLogicConfig({
            id: StrategyIdLib.DEV,
            implementation: address(newStrategyImplementation),
            deployAllowed: true,
            upgradeAllowed: false,
            farming: false,
            tokenId: type(uint).max
        }), address(this));

        strategyProxyHash = IStrategyProxy(strategy).STRATEGY_IMPLEMENTATION_LOGIC_ID_HASH();
        vm.expectRevert(abi.encodeWithSelector(IFactory.UpgradeDenied.selector, strategyProxyHash));
        factory.upgradeStrategyProxy(strategy); 

        factory.setStrategyLogicConfig(IFactory.StrategyLogicConfig({
            id: StrategyIdLib.DEV,
            implementation: address(newStrategyImplementation),
            deployAllowed: true,
            upgradeAllowed: true,
            farming: false,
            tokenId: type(uint).max
        }), address(this));

        factory.upgradeStrategyProxy(strategy);
    }

    function testFarms() public {
        assertEq(factory.farmsLength(), 0);
        IFactory.Farm memory farm;
        IFactory.Farm[] memory farms = new IFactory.Farm[](1);
        farms[0] = IFactory.Farm({
            status: 0,
            pool: address(1),
            strategyLogicId: StrategyIdLib.DEV,
            rewardAssets: new address[](1),
            addresses: new address[](0),
            nums: new uint[](0),
            ticks: new int24[](0)
        });

        factory.addFarms(farms);
        assertEq(factory.farmsLength(), 1);
        farm = factory.farm(0);
        assertEq(farm.pool, address(1));

        farm.pool = address(3);
        factory.updateFarm(0, farm);
        farm = factory.farm(0);
        assertEq(farm.pool, address(3));

        IFactory.Farm[] memory farms_ = factory.farms();
        assertEq(farms_[0].pool, address(3));
    }

    function testSetVaultStatus() public {
        factory.setVaultStatus(address(1), 1);
        assertEq(factory.vaultStatus(address(1)), 1);
    }

    function testDeploymentKey() public view {
        factory.getDeploymentKey(
            '',
            '',
            new address[](0),
            new uint[](0),
            new address[](0),
            new uint[](0),
            new int24[](0)
        );
    }

    function testGetExchangeAssetIndexRequire() public {
        vm.expectRevert(ISwapper.NoRouteFound.selector);
        factory.getExchangeAssetIndex(new address[](0));
    }
}