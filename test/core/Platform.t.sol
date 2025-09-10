// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Platform} from "../../src/core/Platform.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {MockVaultUpgrade} from "../../src/test/MockVaultUpgrade.sol";
import {MockStrategy} from "../../src/test/MockStrategy.sol";
import {Factory} from "../../src/core/Factory.sol";
import {Swapper} from "../../src/core/Swapper.sol";
import {StrategyLogic} from "../../src/core/StrategyLogic.sol";
import {ConstantsLib} from "../../src/core/libs/ConstantsLib.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IStrategyLogic} from "../../src/interfaces/IStrategyLogic.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {StrategyDeveloperLib} from "../../src/strategies/libs/StrategyDeveloperLib.sol";

contract PlatformTest is Test {
    Platform public platform;
    StrategyLogic public strategyLogic;
    MockStrategy public strategyImplementation;
    MockStrategy public strategy;

    function setUp() public {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new Platform()));
        platform = Platform(address(proxy));
        strategyImplementation = new MockStrategy();
        Proxy strategyProxy = new Proxy();
        strategyProxy.initProxy(address(strategyImplementation));
        strategy = MockStrategy(address(strategyProxy));
    }

    function testSetMinTvlForFreeHardWork() public {
        platform.initialize(address(this), "23.11.0-dev");
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotGovernanceAndNotMultisig.selector));
        vm.prank(address(1));
        platform.setMinTvlForFreeHardWork(123);
        platform.setMinTvlForFreeHardWork(123);
        assertEq(platform.minTvlForFreeHardWork(), 123);
    }

    function testSetup() public {
        vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectZeroArgument.selector));
        platform.initialize(address(0), "23.11.0-dev");
        platform.initialize(address(this), "23.11.0-dev");
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        platform.initialize(address(this), "23.11.0-dev");
        assertEq(platform.governance(), address(0));
        assertEq(platform.multisig(), address(this));
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new Platform()));
        Platform platform2 = Platform(address(proxy));
        platform2.initialize(address(this), "23.11.0-dev");
        platform.setup(
            IPlatform.SetupAddresses({
                factory: address(1),
                priceReader: address(2),
                swapper: address(3),
                vaultManager: address(6),
                strategyLogic: address(strategyLogic),
                targetExchangeAsset: address(9),
                hardWorker: address(10),
                zap: address(0),
                revenueRouter: address(1),
                metaVaultFactory: address(0)
            }),
            IPlatform.PlatformSettings({fee: 6_000})
        );

        assertEq(platform.revenueRouter(), address(1));
        platform.setupRevenueRouter(address(1001));
        assertEq(platform.revenueRouter(), address(1001));

        assertEq(platform.ecosystemRevenueReceiver(), address(0));

        vm.expectRevert(abi.encodeWithSelector(IControllable.AlreadyExist.selector));
        platform.setup(
            IPlatform.SetupAddresses({
                factory: address(1),
                priceReader: address(2),
                swapper: address(3),
                vaultManager: address(6),
                strategyLogic: address(strategyLogic),
                targetExchangeAsset: address(9),
                hardWorker: address(10),
                zap: address(0),
                revenueRouter: address(0),
                metaVaultFactory: address(0)
            }),
            IPlatform.PlatformSettings({fee: 6_000})
        );
    }

    function testAddRemoveOperator(address operator) public {
        platform.initialize(address(this), "23.11.0-dev");
        if (operator == address(this)) {
            vm.expectRevert(abi.encodeWithSelector(IControllable.AlreadyExist.selector));
        } else {
            assertEq(platform.isOperator(operator), false);
        }

        platform.addOperator(operator);
        vm.expectRevert(abi.encodeWithSelector(IControllable.AlreadyExist.selector));
        platform.addOperator(operator);

        assertEq(platform.isOperator(operator), true);
        address[] memory operatorsList = platform.operatorsList();

        if (operator == address(this)) {
            assertEq(operatorsList.length, 1);
        } else {
            assertEq(operatorsList.length, 2);
        }

        platform.removeOperator(operator);
        assertEq(platform.isOperator(operator), false);
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotExist.selector));
        platform.removeOperator(operator);

        if (operator != address(0) && operator != address(this)) {
            vm.startPrank(operator);
            vm.expectRevert(abi.encodeWithSelector(IControllable.NotGovernanceAndNotMultisig.selector));
            platform.addOperator(operator);
            vm.stopPrank();
        }
    }

    function testProxyUpgrade(address multisig) public {
        if (multisig != address(0)) {
            platform.initialize(multisig, "23.11.0-dev");

            // its not fabric vault
            CVault vaultImplementation = new CVault();

            MockVaultUpgrade vaultImplementationUpgrade = new MockVaultUpgrade();

            Proxy proxy = new Proxy();
            proxy.initProxy(address(vaultImplementation));
            CVault vault = CVault(payable(address(proxy)));
            vault.initialize(
                IVault.VaultInitializationData({
                    platform: address(platform),
                    strategy: address(strategy),
                    name: "V",
                    symbol: "V",
                    tokenId: 0,
                    vaultInitAddresses: new address[](0),
                    vaultInitNums: new uint[](0)
                })
            );

            address[] memory proxies = new address[](1);
            proxies[0] = address(proxy);
            address[] memory implementations = new address[](1);
            implementations[0] = address(vaultImplementationUpgrade);

            if (multisig != address(this)) {
                vm.expectRevert(abi.encodeWithSelector(IControllable.NotGovernanceAndNotMultisig.selector));
                platform.announcePlatformUpgrade("2025.01.0-beta", proxies, implementations);
            }

            vm.startPrank(multisig);
            platform.announcePlatformUpgrade("2025.01.0-beta", proxies, implementations);

            vm.expectRevert(abi.encodeWithSelector(IPlatform.AlreadyAnnounced.selector));
            platform.announcePlatformUpgrade("2025.01.0-beta", proxies, implementations);

            vm.stopPrank();
            platform.cancelUpgrade();
            vm.startPrank(multisig);

            address[] memory _implementations = new address[](2);
            _implementations[0] = address(vaultImplementationUpgrade);
            _implementations[1] = address(vaultImplementationUpgrade);

            vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectArrayLength.selector));
            platform.announcePlatformUpgrade("2025.01.0-beta", proxies, _implementations);

            address[] memory _proxies = new address[](1);
            _proxies[0] = address(0);
            vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectZeroArgument.selector));
            platform.announcePlatformUpgrade("2025.01.0-beta", _proxies, implementations);

            address[] memory __implementations = new address[](1);
            __implementations[0] = address(0);

            vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectZeroArgument.selector));
            platform.announcePlatformUpgrade("2025.01.0-beta", proxies, __implementations);

            _proxies[0] = address(vaultImplementationUpgrade);
            __implementations[0] = address(vaultImplementationUpgrade);
            vm.expectRevert(abi.encodeWithSelector(IPlatform.SameVersion.selector));
            platform.announcePlatformUpgrade("2025.01.0-beta", _proxies, __implementations);

            string memory oldVersion = platform.platformVersion();
            vm.expectRevert(abi.encodeWithSelector(IPlatform.SameVersion.selector));
            platform.announcePlatformUpgrade(oldVersion, proxies, implementations);

            platform.announcePlatformUpgrade("2025.01.0-beta", proxies, implementations);
            vm.stopPrank();

            assertEq(platform.pendingPlatformUpgrade().proxies[0], address(proxy));
            assertEq(platform.pendingPlatformUpgrade().newImplementations[0], address(vaultImplementationUpgrade));

            platform.cancelUpgrade();
            assertEq(platform.pendingPlatformUpgrade().proxies.length, 0);
            vm.expectRevert(abi.encodeWithSelector(IPlatform.NoNewVersion.selector));
            platform.cancelUpgrade();
            vm.expectRevert(abi.encodeWithSelector(IPlatform.NoNewVersion.selector));
            platform.upgrade();

            vm.prank(multisig);
            platform.announcePlatformUpgrade("2025.01.0-beta", proxies, implementations);

            skip(30 minutes);

            uint TimerTimestamp = platform.platformUpgradeTimelock();
            vm.expectRevert(abi.encodeWithSelector(IPlatform.UpgradeTimerIsNotOver.selector, TimerTimestamp));
            platform.upgrade();

            skip(30 days);

            address notOperator;
            unchecked {
                notOperator = address(uint160(multisig) + 1);
            }
            vm.startPrank(notOperator);
            vm.expectRevert(IControllable.NotOperator.selector);
            platform.upgrade();
            vm.stopPrank();

            platform.upgrade();

            assertEq(proxy.implementation(), address(vaultImplementationUpgrade));
            assertEq(CVault(payable(address(proxy))).VERSION(), "10.99.99");
            assertEq(platform.platformVersion(), "2025.01.0-beta");
        } else {
            vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectZeroArgument.selector));
            platform.initialize(multisig, "23.11.0-dev");
        }
    }

    function testSetFees() public {
        platform.initialize(address(this), "23.11.0-dev");
        address govAddr = platform.governance();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotGovernanceAndNotMultisig.selector));
        platform.setFees(1);

        vm.startPrank(govAddr);
        platform.setFees(6_000);
        (uint fee,,,) = platform.getFees();
        assertEq(fee, 6_000);

        // vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectZeroArgument.selector));
        // platform.setFees(6_000);

        uint _minFee = platform.MIN_FEE();
        uint _maxFee = platform.MAX_FEE();

        vm.expectRevert(abi.encodeWithSelector(IPlatform.IncorrectFee.selector, _minFee, _maxFee));
        platform.setFees(3_000);
        vm.expectRevert(abi.encodeWithSelector(IPlatform.IncorrectFee.selector, _minFee, _maxFee));
        platform.setFees(51_000);

        platform.setCustomVaultFee(address(1), 22_222);
        assertEq(platform.getCustomVaultFee(address(1)), 22_222);

        vm.stopPrank();
    }

    function testGetAmmAdapters() public {
        platform.initialize(address(this), "23.11.0-dev");
        platform.addAmmAdapter("myId", address(1));
        platform.addAmmAdapter("myId2", address(2));
        vm.expectRevert(abi.encodeWithSelector(IControllable.AlreadyExist.selector));
        platform.addAmmAdapter("myId2", address(2));

        (string[] memory ids, address[] memory proxies) = platform.getAmmAdapters();
        assertEq(ids[0], "myId");
        assertEq(ids[1], "myId2");
        assertEq(proxies[0], address(1));
        assertEq(proxies[1], address(2));
    }

    function testGetData() public {
        platform.initialize(address(this), "23.11.0-dev");
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotExist.selector));
        {
            (address[] memory _platformAddresses,,,,,,,,,) = platform.getData();
            delete _platformAddresses;
        }

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new StrategyLogic()));
        strategyLogic = StrategyLogic(address(proxy));
        strategyLogic.init(address(platform));

        proxy = new Proxy();
        proxy.initProxy(address(new Factory()));
        Factory factory = Factory(address(proxy));
        factory.initialize(address(platform));

        proxy = new Proxy();
        proxy.initProxy(address(new Swapper()));
        Swapper _swapper = Swapper(address(proxy));
        _swapper.initialize(address(platform));

        platform.setup(
            IPlatform.SetupAddresses({
                factory: address(factory),
                priceReader: address(2),
                swapper: address(_swapper),
                vaultManager: address(6),
                strategyLogic: address(strategyLogic),
                targetExchangeAsset: address(9),
                hardWorker: address(10),
                zap: address(0),
                revenueRouter: address(0),
                metaVaultFactory: address(0)
            }),
            IPlatform.PlatformSettings({fee: 6_000})
        );

        (
            address[] memory platformAddresses,
            address[] memory bcAssets,
            address[] memory dexAggregators_,
            string[] memory vaultType,
            bytes32[] memory vaultExtra,
            uint[] memory vaultBuildingPrice,
            string[] memory strategyId,
            bool[] memory isFarmingStrategy,
            string[] memory strategyTokenURI,
            bytes32[] memory strategyExtra
        ) = platform.getData();

        assertEq(platformAddresses[0], platform.factory());
        assertEq(platformAddresses[1], platform.vaultManager());
        assertEq(platformAddresses[2], platform.strategyLogic());
        assertEq(platformAddresses[3], address(0)); // deprecated
        assertEq(platformAddresses[4], address(0)); // deprecated
        assertEq(vaultType.length, 0);
        assertEq(bcAssets.length, 0);
        assertEq(dexAggregators_.length, 0);
        assertEq(vaultExtra.length, 0);
        assertEq(vaultBuildingPrice.length, 0);
        assertEq(strategyId.length, 0);
        assertEq(isFarmingStrategy.length, 0);
        assertEq(strategyTokenURI.length, 0);
        assertEq(strategyExtra.length, 0);

        address _logic = platform.strategyLogic();
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotTheOwner.selector));
        IStrategyLogic(_logic).setRevenueReceiver(1, address(1));
        vm.prank(address(0));
        IStrategyLogic(_logic).setRevenueReceiver(1, address(1));
        address _receiver = IStrategyLogic(_logic).getRevenueReceiver(1);
        assertEq(address(1), _receiver);
    }

    function testEcosystemRevenueReceiver() public {
        platform.initialize(address(this), "23.11.0-dev");
        vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectZeroArgument.selector));
        platform.setEcosystemRevenueReceiver(address(0));
        platform.setEcosystemRevenueReceiver(address(1));
    }

    function testDexAggregators() public {
        platform.initialize(address(this), "23.11.0-dev");

        address[] memory dexAggRouter = new address[](2);
        dexAggRouter[0] = address(1);
        dexAggRouter[1] = address(2);
        platform.addDexAggregators(dexAggRouter);

        dexAggRouter[0] = address(8);
        dexAggRouter[1] = address(9);
        platform.addDexAggregators(dexAggRouter);

        address[] memory dexAggs = platform.dexAggregators();
        assertEq(dexAggs.length, 4);
        assertEq(dexAggs[3], address(9));

        assertEq(platform.isAllowedDexAggregatorRouter(address(10)), false);
        assertEq(platform.isAllowedDexAggregatorRouter(address(9)), true);

        dexAggRouter = new address[](1);
        dexAggRouter[0] = address(3);
        platform.addDexAggregators(dexAggRouter);

        dexAggRouter[0] = address(0);
        vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectZeroArgument.selector));
        platform.addDexAggregators(dexAggRouter);

        vm.expectRevert(abi.encodeWithSelector(IPlatform.AggregatorNotExists.selector, address(5)));
        platform.removeDexAggregator(address(5));

        platform.removeDexAggregator(address(1));
        dexAggRouter[0] = address(1);
        platform.addDexAggregators(dexAggRouter);
    }

    function testErc165() public {
        assertEq(platform.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(platform.supportsInterface(type(IControllable).interfaceId), true);

        platform.initialize(address(this), "23.11.0-dev");
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new StrategyLogic()));
        strategyLogic = StrategyLogic(address(proxy));
        strategyLogic.init(address(platform));
        assertEq(strategyLogic.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(strategyLogic.supportsInterface(type(IControllable).interfaceId), true);
        assertEq(strategyLogic.supportsInterface(type(IERC721).interfaceId), true);
        assertEq(strategyLogic.supportsInterface(type(IERC721Enumerable).interfaceId), true);
        assertEq(strategyLogic.supportsInterface(type(IStrategyLogic).interfaceId), true);
    }

    function testOther() public pure {
        assertEq(StrategyDeveloperLib.getDeveloper("unknown"), address(0));
    }
}
