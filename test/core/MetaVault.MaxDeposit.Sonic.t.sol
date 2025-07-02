// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../../chains/sonic/SonicLib.sol";
import "../../src/core/Factory.sol";
import {
MetaVault,
IMetaVault,
IStabilityVault,
IPlatform,
IPriceReader,
IControllable
} from "../../src/core/vaults/MetaVault.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {IchiSwapXFarmStrategy} from "../../src/strategies/IchiSwapXFarmStrategy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MetaVaultFactory} from "../../src/core/MetaVaultFactory.sol";
import {Platform} from "../../src/core/Platform.sol";
import {Swapper} from "../../src/core/Swapper.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SiloFarmStrategy} from "../../src/strategies/SiloFarmStrategy.sol";
import {ISilo} from "../../src/integrations/silo/ISilo.sol";
import {SiloManagedFarmStrategy} from "../../src/strategies/SiloManagedFarmStrategy.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Test, console} from "forge-std/Test.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";
import {MetaUsdAdapter} from "../../src/adapters/MetaUsdAdapter.sol";
import {UniswapV3Adapter} from "../../src/adapters/UniswapV3Adapter.sol";


/// @notice Create MultiVault with SiALMF-vaults
contract MetaVaultMaxDepositSonicTest is Test {
    // uint public constant FORK_BLOCK = 36795243; // Jul-02-2025 03:38:32 AM +UTC
    uint public constant FORK_BLOCK = 36825191; // Jul-02-2025 09:02:59 AM +UTC
    uint public constant MULTI_VAULT_INDEX = 0;
    uint public constant META_VAULT_INDEX = 1;
    uint public constant VALUE_buildingPayPerVaultTokenAmount = 5e24;

    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVaultFactory public metaVaultFactory;
    address[] public metaVaults;
    address[] public wrappedVaults;
    IPriceReader public priceReader;
    address public multisig;
    uint timestamp0;

    struct Strategy {
        string id;
        address pool;
        uint farmId;
        address[] strategyInitAddresses;
        uint[] strategyInitNums;
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        timestamp0 = block.timestamp;

        // we need to skip 1 day to update the swapper
        // but we cannot simply skip 1 day, because the silo oracle will start to revert with InvalidPrice
        vm.warp(timestamp0 - 86400);
    }

    function setUp() public {
        multisig = IPlatform(PLATFORM).multisig();
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);
        Factory factory = Factory(address(IPlatform(PLATFORM).factory()));

        _upgradeSwapperAndAdapter();
        _setupMetaVaultFactory();
        _setupImplementations();
        _updateCVaultImplementation(factory);

        // ------------------------------ Create vaults and strategies
        vm.startPrank(multisig);
        factory.addFarms(_farms());
        {
            IFactory.StrategyAvailableInitParams memory p;
            factory.setStrategyAvailableInitParams(StrategyIdLib.SILO_ALMF_FARM, p);
        }
        SonicLib._addStrategyLogic(factory, StrategyIdLib.SILO_ALMF_FARM, address(new SiloALMFStrategy()), true);
        address[] memory _vaults = _createVaultsAndStrategies(factory);
        vm.stopPrank();

        // ------------------------------ Set up whitelist
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSD);
        for (uint i; i < _vaults.length; ++i) {
            address strategy = address(IVault(_vaults[i]).strategy());
            console.log("VAULT, I, STRATEGY", _vaults[i], i, strategy);

            vm.prank(IPlatform(PLATFORM).multisig());
            IMetaVault(SonicConstantsLib.METAVAULT_metaUSD).changeWhitelist(strategy, true);
        }

        // ------------------------------ Setup swap of metaUSD
        _addAdapter();

        {
            ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());

            vm.startPrank(multisig);
            swapper.addPools(_routes(), false);
            vm.stopPrank();
        }

        // ------------------------------ Create meta vaults and wrappers

        metaVaults = new address[](2);
        wrappedVaults = new address[](2);
        uint[] memory _proportions = new uint[](2);

        // metaUSDC: single USDC lending vaults
        string memory vaultType = VaultTypeLib.MULTIVAULT;
        _proportions[0] = 50e16;
        _proportions[1] = 50e16;
        metaVaults[MULTI_VAULT_INDEX] = _deployMetaVaultByMetaVaultFactory(
            vaultType, SonicConstantsLib.TOKEN_USDC, "Stability USDC", "metaUSDC", _vaults, _proportions
        );
        wrappedVaults[MULTI_VAULT_INDEX] = _deployWrapper(metaVaults[MULTI_VAULT_INDEX]);

        // metaUSD: single MultiVault
        vaultType = VaultTypeLib.METAVAULT;
        _vaults = new address[](1);
        _vaults[0] = metaVaults[MULTI_VAULT_INDEX];
        _proportions = new uint[](1);
        _proportions[0] = 100e16;
        metaVaults[META_VAULT_INDEX] = _deployMetaVaultByMetaVaultFactory(vaultType, address(0), "Stability USD", "metaUSD", _vaults, _proportions);
        wrappedVaults[META_VAULT_INDEX] = _deployWrapper(metaVaults[META_VAULT_INDEX]);
    }

    function testMultiDeposit() public {
        IMetaVault multiVault = IMetaVault(metaVaults[MULTI_VAULT_INDEX]);
        assertEq(multiVault.vaults().length, 2, "MultiVault should have 2 sub-vaults");

        uint[] memory amountMetaVaultTokens;
        uint snapshot;

        // ---- Reduce available liquidity in Silo on 99% (to avoid price impact problems during swap of scUSD to USDC)
        _borrowAlmostAllCash(ISilo(SonicConstantsLib.SILO_VAULT_121_WMETAUSD), ISilo(SonicConstantsLib.SILO_VAULT_121_USDC));
        _borrowAlmostAllCash(ISilo(SonicConstantsLib.SILO_VAULT_125_WMETAUSD), ISilo(SonicConstantsLib.SILO_VAULT_125_scUSD));

        // ------------------------------ Try to deposit 1 decimal
        snapshot = vm.snapshotState();
        amountMetaVaultTokens = new uint[](1);
        amountMetaVaultTokens[0] = 1e18;
        _tryToDeposit(multiVault, amountMetaVaultTokens, false);
        vm.revertToState(snapshot);

        // ------------------------------ Try to deposit max possible amount
        console.log("!!!!!!!!!!!!!!!!!!!!! Try to deposit max possible amount");
        snapshot = vm.snapshotState();
        amountMetaVaultTokens = multiVault.maxDeposit(address(this));
        console.log("maxDeposit", amountMetaVaultTokens[0]);
        _tryToDeposit(multiVault, amountMetaVaultTokens, false);
        vm.revertToState(snapshot);

        // ------------------------------ Try to deposit more than maxDeposit
        console.log("!!!!!!!!!!!!!!!!!!!!! Try to deposit more than maxDeposit");
        snapshot = vm.snapshotState();
        amountMetaVaultTokens = multiVault.maxDeposit(address(this));
        console.log("maxDeposit", amountMetaVaultTokens[0]);
        amountMetaVaultTokens[0] = amountMetaVaultTokens[0] * 110 / 100; // increase by 10%
        console.log("maxDeposit increased", amountMetaVaultTokens[0]);
        _tryToDeposit(multiVault, amountMetaVaultTokens, false);
        vm.revertToState(snapshot);
    }

    //region -------------------------------------------- Internal functions
    function _tryToDeposit(IMetaVault multiVault, uint[] memory maxAmounts, bool shouldRevert) internal {
        console.log("!!!!!!!!!!!!!!!!!!!!! _tryToDeposit", maxAmounts[0]);
        _getMetaUsdOnBalance(address(this), maxAmounts[0], true);

        vm.prank(address(this));
        IMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD).approve(address(multiVault), maxAmounts[0]);

        address[] memory assetsForDeposit = multiVault.assetsForDeposit();

        console.log("balance", IMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD).balanceOf(address(this)));
        console.log("assetsForDeposit", assetsForDeposit[0], SonicConstantsLib.WRAPPED_METAVAULT_metaUSD);

        if (shouldRevert) {
            vm.expectRevert();
        }
        vm.prank(address(this));
        multiVault.depositAssets(assetsForDeposit, maxAmounts, 0, address(this));
    }

    function _getMetaUsdOnBalance(address user, uint amountMetaVaultTokens, bool wrap) internal {
        IMetaVault metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSD);

        // we don't know exact amount of USDC required to receive exact amountMetaVaultTokens
        // so we deposit a bit large amount of USDC
        address[] memory _assets = metaVault.assetsForDeposit();
        uint[] memory amountsMax = new uint[](1);
        amountsMax[0] = 2 * amountMetaVaultTokens / 1e12;

        deal(SonicConstantsLib.TOKEN_USDC, user, amountsMax[0]);

        vm.startPrank(user);
        IERC20(SonicConstantsLib.TOKEN_USDC).approve(
            address(metaVault),
            IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(user)
        );
        metaVault.depositAssets(_assets, amountsMax, 0, user);
        vm.roll(block.number + 6);
        vm.stopPrank();

        if (wrap) {
            vm.startPrank(user);
            IWrappedMetaVault wrappedMetaVault = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD);
            metaVault.approve(address(wrappedMetaVault), metaVault.balanceOf(user));
            wrappedMetaVault.deposit(metaVault.balanceOf(user), user, 0);
            vm.stopPrank();

            vm.roll(block.number + 6);
        }
    }

    function _borrowAlmostAllCash(ISilo collateralVault, ISilo debtVault) internal {
        console.log("!!!!!!!!!!!!_borrowAlmostAllCash");
        address user = address(214385);
        uint maxLiquidityToBorrow = debtVault.getLiquidity();
        uint collateralApproxAmount = 10 * maxLiquidityToBorrow * 1e12;
        _getMetaUsdOnBalance(user, collateralApproxAmount, true);
        console.log("!!!!!!!!!!!!_borrowAlmostAllCash.1");

        uint balance = IERC20(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD).balanceOf(user);

        vm.prank(user);
        IERC20(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD).approve(address(collateralVault), balance);
        console.log("!!!!!!!!!!!!_borrowAlmostAllCash.2");

        vm.prank(user);
        collateralVault.deposit(balance, user);
        console.log("!!!!!!!!!!!!_borrowAlmostAllCash.3");

        vm.prank(user);
        debtVault.borrow(
            maxLiquidityToBorrow * 99 / 100, // borrow 99% of available liquidity
            user,
            user
        );
        console.log("!!!!!!!!!!!!_borrowAlmostAllCash.4");
    }

    //endregion -------------------------------------------- Internal functions

    //region -------------------------------------------- Helper functions
    function _setupMetaVaultFactory() internal {
        vm.prank(multisig);
        Platform(PLATFORM).setupMetaVaultFactory(address(metaVaultFactory));
    }

    function _setupImplementations() internal {
        address metaVaultImplementation = address(new MetaVault());
        address wrappedMetaVaultImplementation = address(new WrappedMetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(metaVaultImplementation);
        vm.prank(multisig);
        metaVaultFactory.setWrappedMetaVaultImplementation(wrappedMetaVaultImplementation);
    }

    function _deployMetaVaultByMetaVaultFactory(
        string memory type_,
        address pegAsset,
        string memory name_,
        string memory symbol_,
        address[] memory vaults_,
        uint[] memory proportions_
    ) internal returns (address metaVaultProxy) {
        vm.prank(multisig);
        return metaVaultFactory.deployMetaVault(
            bytes32(abi.encodePacked(name_)), type_, pegAsset, name_, symbol_, vaults_, proportions_
        );
    }

    function _deployWrapper(address metaVault) internal returns (address wrapper) {
        vm.prank(multisig);
        return metaVaultFactory.deployWrapper(bytes32(uint(uint160(metaVault))), metaVault);
    }

    function _createVaultsAndStrategies(Factory factory) internal returns (address[] memory vaults) {
        deal(IPlatform(PLATFORM).buildingPayPerVaultToken(), address(this), VALUE_buildingPayPerVaultTokenAmount);
        IERC20(IPlatform(PLATFORM).buildingPayPerVaultToken()).approve(address(factory), VALUE_buildingPayPerVaultTokenAmount);

        uint farmId = factory.farmsLength() - 2;
        Strategy[] memory strategies = new Strategy[](2);
        strategies[0] = Strategy({
            id: StrategyIdLib.SILO_ALMF_FARM,
            pool: address(0),
            farmId: farmId,
            strategyInitAddresses: new address[](0),
            strategyInitNums: new uint[](0)
        });
        strategies[1] = Strategy({
            id: StrategyIdLib.SILO_ALMF_FARM,
            pool: address(0),
            farmId: farmId + 1,
            strategyInitAddresses: new address[](0),
            strategyInitNums: new uint[](0)
        });

        vaults = new address[](strategies.length);
        for (uint i; i < strategies.length; ++i) {
            IFactory.StrategyLogicConfig memory strategyConfig = factory.strategyLogicConfig(keccak256(bytes(strategies[i].id)));
            assertNotEq(
                strategyConfig.implementation, address(0), "Strategy implementation not found: put it to chain lib."
            );

            string[] memory types = IStrategy(strategyConfig.implementation).supportedVaultTypes();
            assertEq(types.length, 1, "Assume that the strategy supports only one vault type");

            address[] memory vaultInitAddresses = new address[](0);
            uint[] memory vaultInitNums = new uint[](0);
            address[] memory initStrategyAddresses;
            uint[] memory nums;
            int24[] memory ticks = new int24[](0);

            // farming
            nums = new uint[](1);
            nums[0] = strategies[i].farmId;

            factory.deployVaultAndStrategy(
                types[0],
                strategies[i].id,
                vaultInitAddresses,
                vaultInitNums,
                initStrategyAddresses,
                nums,
                ticks
            );

            vaults[i] = factory.deployedVault(factory.deployedVaultsLength() - 1);
        }
    }

    function _farms() internal pure returns (IFactory.Farm[] memory destFarms) {
        destFarms = new IFactory.Farm[](2);

        destFarms[0] = SonicFarmMakerLib._makeSiloALMFarm(
            SonicConstantsLib.SILO_VAULT_121_WMETAUSD,
            SonicConstantsLib.SILO_VAULT_121_USDC,
            SonicConstantsLib.BEETS_VAULT, // todo
            SonicConstantsLib.SILO_LENS // todo
        );

        destFarms[1] = SonicFarmMakerLib._makeSiloALMFarm(
            SonicConstantsLib.SILO_VAULT_125_WMETAUSD,
            SonicConstantsLib.SILO_VAULT_125_scUSD,
            SonicConstantsLib.BEETS_VAULT, // todo
            SonicConstantsLib.SILO_LENS // todo
        );
    }

    function _updateCVaultImplementation(IFactory factory) internal {
        address vaultImplementation = address(new CVault());
        vm.prank(multisig);
        factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: VaultTypeLib.COMPOUNDING,
                implementation: vaultImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: 1e10
            })
        );
    }

    function _upgradeMetaVault(address metaVault_) internal {
        // Upgrade MetaVault to the new implementation
        address vaultImplementation = address(new MetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);
        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault_);
        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);
    }

    function _addAdapter() internal returns (address adapter) {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new MetaUsdAdapter()));
        MetaUsdAdapter(address(proxy)).init(PLATFORM);

        vm.prank(multisig);
        IPlatform(PLATFORM).addAmmAdapter(AmmAdapterIdLib.META_USD, address(proxy));

        return address(proxy);
    }

    function _routes() internal pure returns (ISwapper.AddPoolData[] memory pools) {
        pools = new ISwapper.AddPoolData[](2);
        uint i;
        pools[i++] = _makePoolData(
            SonicConstantsLib.METAVAULT_metaUSD,
            AmmAdapterIdLib.META_USD,
            SonicConstantsLib.METAVAULT_metaUSD,
            SonicConstantsLib.METAVAULT_metaUSD
        );
        pools[i++] = _makePoolData(
            SonicConstantsLib.WRAPPED_METAVAULT_metaUSD,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.WRAPPED_METAVAULT_metaUSD,
            SonicConstantsLib.METAVAULT_metaUSD
        );
    }

    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return ISwapper.AddPoolData({pool: pool, ammAdapterId: ammAdapterId, tokenIn: tokenIn, tokenOut: tokenOut});
    }

    function _upgradeSwapperAndAdapter() internal {
        address[] memory proxies = new address[](2);
        proxies[0] = address(IPlatform(PLATFORM).swapper());
        bytes32 hash = keccak256(bytes(AmmAdapterIdLib.UNISWAPV3));
        proxies[1] = address(IPlatform(PLATFORM).ammAdapter(hash).proxy);

        address[] memory implementations = new address[](2);
        implementations[0] = address(new Swapper());
        implementations[1] = address(new UniswapV3Adapter());

        vm.prank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.03.1-alpha", proxies, implementations);

        skip(1 days);

        vm.prank(multisig);
        IPlatform(PLATFORM).upgrade();
    }
    //endregion -------------------------------------------- Helper functions
}
