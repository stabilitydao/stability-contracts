// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {Platform} from "../../src/core/Platform.sol";
import "../../src/core/proxy/Proxy.sol";
import "../../src/core/vaults/CVault.sol";
import "../../src/test/MockVaultUpgrade.sol";
import "../../src/test/MockStrategy.sol";
import "../../src/core/Factory.sol";
import "../../src/core/Swapper.sol";
import "../../src/core/StrategyLogic.sol";
import "../../src/core/libs/ConstantsLib.sol";
import "../../src/interfaces/IControllable.sol";
import "../../src/strategies/libs/StrategyDeveloperLib.sol";

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
                buildingPermitToken: address(4),
                buildingPayPerVaultToken: address(5),
                vaultManager: address(6),
                strategyLogic: address(strategyLogic),
                aprOracle: address(8),
                targetExchangeAsset: address(9),
                hardWorker: address(10),
                rebalancer: address(101),
                zap: address(0),
                bridge: address(102)
            }),
            IPlatform.PlatformSettings({
                networkName: "Localhost Ethereum",
                networkExtra: CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x7746d7), bytes3(0x040206))),
                fee: 6_000,
                feeShareVaultManager: 30_000,
                feeShareStrategyLogic: 30_000,
                feeShareEcosystem: 0,
                minInitialBoostPerDay: 30e18, // $30
                minInitialBoostDuration: 30 * 86400 // 30 days
            })
        );
        assertEq(platform.minInitialBoostPerDay(), 30e18);
        platform.setInitialBoost(31e18, 31 * 86400);
        assertEq(platform.minInitialBoostPerDay(), 31e18);
        assertEq(platform.minInitialBoostDuration(), 31 * 86400);

        assertEq(platform.rebalancer(), address(101));
        assertEq(platform.bridge(), address(102));

        platform.setupRebalancer(address(1001));
        platform.setupBridge(address(1002));

        assertEq(platform.rebalancer(), address(1001));
        assertEq(platform.bridge(), address(1002));

        assertEq(platform.networkName(), "Localhost Ethereum");
        assertEq(
            platform.networkExtra(), CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x7746d7), bytes3(0x040206)))
        );

        assertEq(platform.ecosystemRevenueReceiver(), address(0));

        vm.expectRevert(abi.encodeWithSelector(IControllable.AlreadyExist.selector));
        platform.setup(
            IPlatform.SetupAddresses({
                factory: address(1),
                priceReader: address(2),
                swapper: address(3),
                buildingPermitToken: address(4),
                buildingPayPerVaultToken: address(5),
                vaultManager: address(6),
                strategyLogic: address(strategyLogic),
                aprOracle: address(8),
                targetExchangeAsset: address(9),
                hardWorker: address(10),
                rebalancer: address(0),
                zap: address(0),
                bridge: address(0)
            }),
            IPlatform.PlatformSettings({
                networkName: "Localhost Ethereum",
                networkExtra: bytes32(0),
                fee: 6_000,
                feeShareVaultManager: 30_000,
                feeShareStrategyLogic: 30_000,
                feeShareEcosystem: 0,
                minInitialBoostPerDay: 30e18, // $30
                minInitialBoostDuration: 30 * 86400 // 30 days
            })
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

            vm.startPrank(address(100));
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
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotGovernance.selector));
        platform.setFees(1, 1, 1, 1);

        vm.startPrank(govAddr);
        platform.setFees(6_000, 30_000, 30_000, 0);
        (uint fee, uint feeShareVaultManager, uint feeShareStrategyLogic, uint feeShareEcosystem) = platform.getFees();
        assertEq(fee, 6_000);
        assertEq(feeShareVaultManager, 30_000);
        assertEq(feeShareStrategyLogic, 30_000);
        assertEq(feeShareEcosystem, 0);

        vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectZeroArgument.selector));
        platform.setFees(6_000, 30_000, 30_000, 5);

        uint _minFee = platform.MIN_FEE();
        uint _maxFee = platform.MAX_FEE();

        vm.expectRevert(abi.encodeWithSelector(IPlatform.IncorrectFee.selector, _minFee, _maxFee));
        platform.setFees(3_000, 30_000, 30_000, 0);
        vm.expectRevert(abi.encodeWithSelector(IPlatform.IncorrectFee.selector, _minFee, _maxFee));
        platform.setFees(51_000, 19_000, 30_000, 0);

        _minFee = platform.MIN_FEE_SHARE_VAULT_MANAGER();
        vm.expectRevert(abi.encodeWithSelector(IPlatform.IncorrectFee.selector, _minFee, 0));
        platform.setFees(6_000, 3_000, 30_000, 0);

        _minFee = platform.MIN_FEE_SHARE_STRATEGY_LOGIC();
        vm.expectRevert(abi.encodeWithSelector(IPlatform.IncorrectFee.selector, _minFee, 0));
        platform.setFees(6_000, 30_000, 3_000, 0);

        _maxFee = ConstantsLib.DENOMINATOR;
        vm.expectRevert(abi.encodeWithSelector(IPlatform.IncorrectFee.selector, 0, _maxFee));
        platform.setFees(10_000, 60_000, 50_000, 0);

        platform.setCustomVaultFee(address(1), 22_222);
        assertEq(platform.getCustomVaultFee(address(1)), 22_222);

        vm.stopPrank();
    }

    function testAddRemoveUseAllowedBBToken() public {
        platform.initialize(address(this), "23.11.0-dev");
        platform.setAllowedBBTokenVaults(address(1), 5);
        platform.setAllowedBBTokenVaults(address(2), 5);
        platform.setAllowedBBTokenVaults(address(3), 1);

        vm.startPrank(address(platform.factory()));
        platform.useAllowedBBTokenVault(address(3));
        vm.expectRevert(abi.encodeWithSelector(IPlatform.NotEnoughAllowedBBToken.selector));
        platform.useAllowedBBTokenVault(address(3));
        vm.stopPrank();

        (address[] memory bbToken,) = platform.allowedBBTokenVaults();
        assertEq(bbToken[0], address(1));
        assertEq(bbToken[1], address(2));

        vm.expectRevert(abi.encodeWithSelector(IControllable.NotExist.selector));
        platform.removeAllowedBBToken(address(5));

        platform.removeAllowedBBToken(bbToken[0]);

        (bbToken,) = platform.allowedBBTokenVaults();
        //EnumerableSet.remove change positions inside array
        assertEq(bbToken[0], address(3));
        assertEq(bbToken[1], address(2));

        platform.removeAllowedBBToken(bbToken[0]);
        (bbToken,) = platform.allowedBBTokenVaults();
        assertEq(bbToken.length, 1);
        platform.removeAllowedBBToken(bbToken[0]);
        (bbToken,) = platform.allowedBBTokenVaults();
        assertEq(bbToken.length, 0);

        vm.expectRevert(IControllable.NotFactory.selector);
        platform.useAllowedBBTokenVault(address(100));
    }

    function testAddRemoveAllowedBoostRewardToken() public {
        platform.initialize(address(this), "23.11.0-dev");
        platform.addAllowedBoostRewardToken(address(1));
        platform.addAllowedBoostRewardToken(address(2));

        vm.expectRevert(abi.encodeWithSelector(IControllable.AlreadyExist.selector));
        platform.addAllowedBoostRewardToken(address(2));
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotExist.selector));
        platform.removeAllowedBoostRewardToken(address(789));

        address[] memory allowedTokens = platform.allowedBoostRewardTokens();
        assertEq(allowedTokens[0], address(1));
        assertEq(allowedTokens[1], address(2));

        platform.removeAllowedBoostRewardToken(address(1));
        allowedTokens = platform.allowedBoostRewardTokens();
        assertEq(allowedTokens[0], address(2));

        platform.removeAllowedBoostRewardToken(address(2));
        allowedTokens = platform.allowedBoostRewardTokens();
        assertEq(allowedTokens.length, 0);
    }

    function testAddRemoveDefaultBoostRewardToken() public {
        platform.initialize(address(this), "23.11.0-dev");
        platform.addDefaultBoostRewardToken(address(1));
        platform.addDefaultBoostRewardToken(address(2));

        vm.expectRevert(abi.encodeWithSelector(IControllable.AlreadyExist.selector));
        platform.addDefaultBoostRewardToken(address(2));
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotExist.selector));
        platform.removeDefaultBoostRewardToken(address(789));

        address[] memory defaultTokens = platform.defaultBoostRewardTokens();
        assertEq(defaultTokens[0], address(1));
        assertEq(defaultTokens[1], address(2));

        platform.removeDefaultBoostRewardToken(address(1));
        defaultTokens = platform.defaultBoostRewardTokens();
        assertEq(defaultTokens[0], address(2));

        platform.removeDefaultBoostRewardToken(address(2));
        defaultTokens = platform.defaultBoostRewardTokens();
        assertEq(defaultTokens.length, 0);
    }

    function testAddBoostTokens() public {
        address[] memory allowedBoostRewardTokens = new address[](2);
        allowedBoostRewardTokens[0] = address(101);
        allowedBoostRewardTokens[1] = address(105);
        address[] memory defaultBoostRewardTokens = new address[](1);
        defaultBoostRewardTokens[0] = address(208);

        platform.initialize(address(this), "23.11.0-dev");
        platform.addBoostTokens(allowedBoostRewardTokens, defaultBoostRewardTokens);

        address[] memory alreadyAddedAllowedBoostRewardToken = new address[](1);
        alreadyAddedAllowedBoostRewardToken[0] = address(101);
        address[] memory newDefaultBoostRewardTokens = new address[](1);
        newDefaultBoostRewardTokens[0] = address(386);
        vm.expectRevert(abi.encodeWithSelector(IPlatform.TokenAlreadyExistsInSet.selector, address(101)));
        platform.addBoostTokens(alreadyAddedAllowedBoostRewardToken, newDefaultBoostRewardTokens);

        address[] memory defaultTokens = platform.defaultBoostRewardTokens();
        assertEq(defaultTokens.length, 1);
        assertEq(defaultTokens[0], address(208));

        address[] memory allowedTokens = platform.allowedBoostRewardTokens();
        assertEq(allowedTokens.length, 2);
        assertEq(allowedTokens[0], address(101));
        assertEq(allowedTokens[1], address(105));
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
                buildingPermitToken: address(4),
                buildingPayPerVaultToken: address(5),
                vaultManager: address(6),
                strategyLogic: address(strategyLogic),
                aprOracle: address(8),
                targetExchangeAsset: address(9),
                hardWorker: address(10),
                rebalancer: address(0),
                zap: address(0),
                bridge: address(0)
            }),
            IPlatform.PlatformSettings({
                networkName: "Localhost Ethereum",
                networkExtra: CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x7746d7), bytes3(0x040206))),
                fee: 6_000,
                feeShareVaultManager: 30_000,
                feeShareStrategyLogic: 30_000,
                feeShareEcosystem: 0,
                minInitialBoostPerDay: 30e18, // $30
                minInitialBoostDuration: 30 * 86400 // 30 days
            })
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
        assertEq(platformAddresses[3], platform.buildingPermitToken());
        assertEq(platformAddresses[4], platform.buildingPayPerVaultToken());
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
