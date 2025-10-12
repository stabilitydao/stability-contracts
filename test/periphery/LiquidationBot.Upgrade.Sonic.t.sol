// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {BrunchAdapter} from "../../src/adapters/BrunchAdapter.sol";
import {Aave3PriceOracleMock} from "../../src/test/Aave3PriceOracleMock.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IAaveAddressProvider} from "../../src/integrations/aave/IAaveAddressProvider.sol";
import {IAaveDataProvider} from "../../src/integrations/aave/IAaveDataProvider.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";
import {IAavePriceOracle} from "../../src/integrations/aave/IAavePriceOracle.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {ILiquidationBot} from "../../src/interfaces/ILiquidationBot.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {LiquidationBotLib} from "../../src/periphery/libs/LiquidationBotLib.sol";
import {LiquidationBot} from "../../src/periphery/LiquidationBot.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {AmmAdapterIdLib} from "../../src/adapters/AlgebraV4Adapter.sol";
import {SonicLib} from "../../chains/sonic/SonicLib.sol";
import {console} from "forge-std/console.sol";

contract LendingBotUpdateSonicTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;

    /// @dev This block is used if there is no LENDING_BATCH_TEST_SONIC_BLOCK env var set
    uint public constant FORK_BLOCK = 50328814; // Oct-12-2025 02:40:46 PM +UTC

    IFactory public factory;
    address public multisig;
    uint public selectedBlock;

    address internal constant STABILITY_POOL = SonicConstantsLib.STABILITY_USD_MARKET_GEN2_POOL;

    address internal constant BRUNCH_POOL = SonicConstantsLib.BRUNCH_GEN2_POOL;

    address internal constant USER = address(0x314159265358979323846);
    address internal constant OTHER_USER = address(0x271828182845904523536);
    address internal constant PROFIT_TARGET = address(0x123456789012345678901);

    uint internal constant BASE_DEPOSIT_AMOUNT_WITHOUT_DECIMALS = 1000;
    uint internal constant PRICE_IMPACT_TOLERANCE = 3_000; // 3%

    /// @notice 0 - use max repay
    uint internal constant TARGET_HEALTH_FACTOR_18 = 0;

    /// @notice All pools to be tested, list is filled in the constructor
    address[2] POOLS;

    //region ---------------------- Data types
    struct UserAccountData {
        uint totalCollateralBase;
        uint totalDebtBase;
        uint availableBorrowsBase;
        uint currentLiquidationThreshold;
        uint ltv;
        uint healthFactor;
    }

    struct LendingPosition {
        address collateralAsset;
        address borrowAsset;
        uint collateralAmount;
        UserAccountData userAccountData;
        bool depositDone;
        bool borrowDone;
        uint providedBorrowLiquidity;
        uint borrowLiquidityRemoved;
        string error;
    }

    struct Results {
        address pool;
        LendingPosition position;
        uint healthFactorAfterForwardingTime;
        UserAccountData userAccountData;
        uint botProfitInBorrowAsset;
        bool liquidationDone;
        string error;
        string errorOtherUser;
    }
    //endregion ---------------------- Data types

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        selectedBlock = block.number;

        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();

        POOLS = [SonicConstantsLib.STABILITY_USD_MARKET_GEN2_POOL, SonicConstantsLib.BRUNCH_GEN2_POOL];
    }

    function testStateMetaUsdGen2() public view {
        address[2] memory topUsers =
            [0x65B5c75e1391cA3315C762482DA58b0c53C63fd7, 0x88888887C3ebD4a33E34a15Db4254C74C75E5D4A];
        for (uint i; i < topUsers.length; ++i) {
            (,,,, uint ltv, uint healthFactor) =
                IPool(SonicConstantsLib.STABILITY_USD_MARKET_GEN2_POOL).getUserAccountData(topUsers[i]);
            console.log("stability", topUsers[i], healthFactor, ltv);
        }
    }

    function testStateBrunchGen2() public view {
        address[3] memory topUsers = [
            0x5123525EF2065C01Dd3A24565D6ED560EEA833C1,
            0x40dc1c6695F5D9e7B9Bfe1F127c2E66ABB76D11A,
            0xC0eFE789CD98B390df49771d55a146dE03aD0580
        ];
        for (uint i; i < topUsers.length; ++i) {
            (,,,, uint ltv, uint healthFactor) =
                IPool(SonicConstantsLib.BRUNCH_GEN2_POOL).getUserAccountData(topUsers[i]);
            console.log("brunch", topUsers[i], healthFactor, ltv);
        }
    }

    function testWMetaUsd() public {
        address holder = 0x65B5c75e1391cA3315C762482DA58b0c53C63fd7;

        ILiquidationBot bot1 = _getBotInstance(false);
        {
            (address flashLoanVault, uint flashLoanKind) = bot1.getFlashLoanVault();
            console.log("exist flashLoanVault", flashLoanVault, flashLoanKind);
            console.log("exist health factor", bot1.targetHealthFactor());
        }

        ILiquidationBot bot = _getBotInstance(true);
        {
            (address flashLoanVault, uint flashLoanKind) = bot.getFlashLoanVault();
            console.log("flashLoanVault", flashLoanVault, flashLoanKind);
            console.log("health factor", bot.targetHealthFactor());
        }

        _testLiquidation(
            SonicConstantsLib.STABILITY_USD_MARKET_GEN2_POOL,
            bot,
            BASE_DEPOSIT_AMOUNT_WITHOUT_DECIMALS,
            holder,
            type(uint).max
        );
    }

    function testBrunch() public {
        address holder = 0x5123525EF2065C01Dd3A24565D6ED560EEA833C1;

        // ----------------- replace price oracle to fix prices life time
        LiquidationBotLib.AaveContracts memory ac =
            LiquidationBotLib.getAaveContracts(SonicConstantsLib.BRUNCH_GEN2_POOL);
        _replacePriceOracle(ac);

        // ----------------- move time until health factor < 1
        for (uint i; i < 256; ++i) {
            (,,,,, uint healthFactorAfterForwardingTime) =
                IPool(SonicConstantsLib.BRUNCH_GEN2_POOL).getUserAccountData(holder);
            console.log("healthFactorAfterForwardingTime", healthFactorAfterForwardingTime);
            if (healthFactorAfterForwardingTime < 1e18) break;

            vm.warp(block.timestamp + 1 * 3600);
        }

        ILiquidationBot bot = _getBotInstance(true);

        uint targetHealthFactor = 0.998e18; // 997855043180505548; // type(uint).max;

        //        vm.prank(multisig);
        //        bot.setFlashLoanVault(SonicConstantsLib.BEETS_VAULT_V3, uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1));

        vm.prank(multisig);
        bot.setFlashLoanVault(
            SonicConstantsLib.POOL_ALGEBRA_WS_USDC, uint(ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3)
        );

        _testLiquidation(
            SonicConstantsLib.BRUNCH_GEN2_POOL, bot, BASE_DEPOSIT_AMOUNT_WITHOUT_DECIMALS, holder, targetHealthFactor
        );
        // _testLiquidation(SonicConstantsLib.BRUNCH_GEN2_POOL, bot, BASE_DEPOSIT_AMOUNT_WITHOUT_DECIMALS, holder, 998055043180505548);
    }

    //region ---------------------- Internal logic

    function _testLiquidation(
        address pool,
        ILiquidationBot bot,
        uint amountToDepositWithoutDecimals,
        address holder_,
        uint targetHealthFactor_
    ) internal returns (Results memory ret) {
        LiquidationBotLib.AaveContracts memory ac = LiquidationBotLib.getAaveContracts(pool);

        // ----------------- create lending position
        ret.pool = pool;

        // ----------------- make liquidation
        address[] memory users = new address[](1);
        users[0] = holder_;

        bot.liquidate(pool, users, targetHealthFactor_);
        console.log("done");

        // ret.botProfitInBorrowAsset = IERC20(ret.position.borrowAsset).balanceOf(bot.profitTarget());
        (
            ret.userAccountData.totalCollateralBase,
            ret.userAccountData.totalDebtBase,
            ret.userAccountData.availableBorrowsBase,
            ret.userAccountData.currentLiquidationThreshold,
            ret.userAccountData.ltv,
            ret.userAccountData.healthFactor
        ) = IPool(pool).getUserAccountData(holder_);

        console.log("after liquidation health factor", ret.userAccountData.healthFactor);
        return ret;
    }

    //endregion ---------------------- Internal logic

    //region ---------------------- Auxiliary functions
    function _replacePriceOracle(LiquidationBotLib.AaveContracts memory ac) internal {
        IAaveAddressProvider addressProvider = IAaveAddressProvider(ac.pool.ADDRESSES_PROVIDER());

        IAavePriceOracle oracle = IAavePriceOracle(addressProvider.getPriceOracle());

        Aave3PriceOracleMock mockOracle = new Aave3PriceOracleMock(address(oracle));

        vm.prank(addressProvider.owner());
        addressProvider.setPriceOracle(address(mockOracle));
    }

    function _getAssets(LiquidationBotLib.AaveContracts memory ac)
        internal
        view
        returns (address collateralAsset, address borrowAsset)
    {
        IAaveDataProvider.TokenData[] memory assets = ac.dataProvider.getAllReservesTokens();
        for (uint i; i < assets.length; ++i) {
            (,,,,, bool usageAsCollateralEnabled, bool borrowingEnabled,,,) =
                ac.dataProvider.getReserveConfigurationData(assets[i].tokenAddress);
            if (usageAsCollateralEnabled && !borrowingEnabled) {
                collateralAsset = assets[i].tokenAddress;
            } else if (!usageAsCollateralEnabled && borrowingEnabled) {
                borrowAsset = assets[i].tokenAddress;
            }
        }

        return (collateralAsset, borrowAsset);
    }

    function _getDefaultAmountToDeposit(address asset_, uint amountNoDecimals) internal view returns (uint) {
        return amountNoDecimals * 10 ** IERC20Metadata(asset_).decimals();
    }
    //endregion ---------------------- Auxiliary functions

    //region ---------------------- Setup bot
    /// @notice Create and set up liquidation bot instance.
    function _getBotInstance(bool newInstance) internal returns (ILiquidationBot) {
        if (newInstance) {
            ILiquidationBot bot = _createLiquidationBotInstance();
            _setUpLiquidationBot(
                bot,
                SonicConstantsLib.POOL_SHADOW_CL_USDC_USDT,
                uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2),
                1000001000000000000
            );
            //            _addAdapter();
            //            _addRoutes();

            return bot;
        } else {
            ILiquidationBot bot = ILiquidationBot(SonicConstantsLib.LIQUIDATION_BOT);

            vm.prank(multisig);
            bot.changeWhitelist(address(this), true); // todo use exist whitelisted address

            return bot;
        }
    }

    function _createLiquidationBotInstance() internal returns (ILiquidationBot) {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new LiquidationBot()));

        ILiquidationBot bot = ILiquidationBot(address(proxy));
        bot.initialize(SonicConstantsLib.PLATFORM);

        return bot;
    }

    function _setUpLiquidationBot(
        ILiquidationBot bot,
        address flashLoanVault,
        uint flashLoanKind,
        uint targetHealthFactor_
    ) internal {
        vm.prank(multisig);
        bot.changeWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, true);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSD).changeWhitelist(address(bot), true);

        vm.prank(multisig);
        bot.setTargetHealthFactor(targetHealthFactor_);

        vm.prank(multisig);
        bot.setProfitTarget(PROFIT_TARGET);

        vm.prank(multisig);
        bot.setFlashLoanVault(flashLoanVault, flashLoanKind);

        vm.prank(multisig);
        bot.changeWhitelist(address(this), true);

        vm.prank(multisig);
        bot.setPriceImpactTolerance(PRICE_IMPACT_TOLERANCE);
    }

    function _addAdapter() internal returns (BrunchAdapter adapter) {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BrunchAdapter()));
        BrunchAdapter(address(proxy)).init(SonicConstantsLib.PLATFORM);
        multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();

        adapter = BrunchAdapter(address(proxy));

        vm.prank(multisig);
        IPlatform(SonicConstantsLib.PLATFORM).addAmmAdapter(AmmAdapterIdLib.BRUNCH, address(proxy));
    }

    function _addRoutes() internal {
        ISwapper swapper = ISwapper(IPlatform(SonicConstantsLib.PLATFORM).swapper());

        ISwapper.AddPoolData[] memory pools = new ISwapper.AddPoolData[](2);
        pools[0] = SonicLib._makePoolData(
            SonicConstantsLib.POOL_SHADOW_USDC_BRUNCH_USDC,
            AmmAdapterIdLib.SOLIDLY,
            SonicConstantsLib.TOKEN_BRUNCH_USD,
            SonicConstantsLib.TOKEN_USDC
        );
        pools[1] = SonicLib._makePoolData(
            SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD,
            AmmAdapterIdLib.BRUNCH,
            SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD,
            SonicConstantsLib.TOKEN_BRUNCH_USD
        );

        vm.prank(multisig);
        swapper.addPools(pools, false);
    }
    //endregion ---------------------- Setup bot
}
