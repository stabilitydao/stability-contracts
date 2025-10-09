// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm, Test} from "forge-std/Test.sol";
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

/// @notice Test all given lending markets for liquidation
contract LendingBatchSonicSkipOnCiTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;

    /// @dev This block is used if there is no LENDING_BATCH_TEST_SONIC_BLOCK env var set
    uint public constant FORK_BLOCK = 49863166; // Oct-09-2025 06:54:18 AM +UTC

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
        // ---------------- select block for test
        uint _block = vm.envOr("LENDING_BATCH_TEST_SONIC_BLOCK", uint(FORK_BLOCK));
        if (_block == 0) {
            // use latest block if LENDING_BATCH_TEST_SONIC_BLOCK is set to 0
            vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        } else {
            // use block from LENDING_BATCH_TEST_SONIC_BLOCK or pre-defined block if LENDING_BATCH_TEST_SONIC_BLOCK is not set
            vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), _block));
        }
        selectedBlock = block.number;

        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();

        POOLS = [SonicConstantsLib.STABILITY_USD_MARKET_GEN2_POOL, SonicConstantsLib.BRUNCH_GEN2_POOL];
    }

    function testLiquidationBatch() public {
        uint count = 3;
        Results[] memory rets = new Results[](POOLS.length * count);

        ILiquidationBot bot = _getBotInstance();

        for (uint i = 0; i < POOLS.length; i++) {
            for (uint a = 0; a < count; ++a) {
                uint snapshot = vm.snapshotState();
                rets[i * 3 + a] = _testLiquidation(POOLS[i], bot, BASE_DEPOSIT_AMOUNT_WITHOUT_DECIMALS * 10 ** a);
                vm.revertToState(snapshot);
                console.log("Pool processed:", a, i, POOLS[i]);
            }
        }

        saveToCsv("Lending.Batch.Sonic.results.csv", rets, bot);
    }

    function testSingleLiquidation() internal {
        ILiquidationBot bot = _getBotInstance();
        _testLiquidation(SonicConstantsLib.BRUNCH_GEN2_POOL, bot, BASE_DEPOSIT_AMOUNT_WITHOUT_DECIMALS);
    }

    //region ---------------------- Internal logic

    function _testLiquidation(
        address pool,
        ILiquidationBot bot,
        uint amountToDepositWithoutDecimals
    ) internal returns (Results memory ret) {
        LiquidationBotLib.AaveContracts memory ac = LiquidationBotLib.getAaveContracts(pool);

        // ----------------- create lending position
        ret.pool = pool;
        ret.position = _createLendingPosition(ac, pool, amountToDepositWithoutDecimals);
        // console.log(ret.position.totalCollateralBase, ret.position.totalDebtBase, ret.position.healthFactor);

        // ----------------- replace price oracle to fix prices life time
        _replacePriceOracle(ac);

        // ----------------- move time until health factor < 1
        for (uint i; i < 256; ++i) {
            (,,,,, ret.healthFactorAfterForwardingTime) = IPool(pool).getUserAccountData(USER);
            if (ret.healthFactorAfterForwardingTime < 1e18) break;

            vm.warp(block.timestamp + 1 * 7 * 24 * 3600);
        }

        if (ret.healthFactorAfterForwardingTime < 1e18) {
            // ----------------- make liquidation

            address[] memory users = new address[](1);
            users[0] = USER;

            try bot.liquidate(pool, users) {
                ret.liquidationDone = true;
            } catch Error(string memory reason) {
                ret.error = reason;
            } catch (bytes memory reason) {
                ret.error = string(
                    abi.encodePacked("Liquidation custom error: ", Strings.toHexString(uint32(bytes4(reason)), 4))
                );
            }
        }

        ret.botProfitInBorrowAsset = IERC20(ret.position.borrowAsset).balanceOf(PROFIT_TARGET);
        (
            ret.userAccountData.totalCollateralBase,
            ret.userAccountData.totalDebtBase,
            ret.userAccountData.availableBorrowsBase,
            ret.userAccountData.currentLiquidationThreshold,
            ret.userAccountData.ltv,
            ret.userAccountData.healthFactor
        ) = IPool(pool).getUserAccountData(USER);

        return ret;
    }

    function _createLendingPosition(
        LiquidationBotLib.AaveContracts memory ac,
        address pool,
        uint amountNoDecimal
    ) internal returns (LendingPosition memory dest) {
        (dest.collateralAsset, dest.borrowAsset) = _getAssets(ac);
        uint amount = _getDefaultAmountToDeposit(dest.collateralAsset, amountNoDecimal);

        deal(dest.collateralAsset, USER, amount);

        vm.prank(USER);
        IERC20(dest.collateralAsset).approve(pool, amount);

        vm.prank(USER);
        try IPool(pool).deposit(dest.collateralAsset, amount, USER, 0) {
            dest.collateralAmount = amount;
            dest.depositDone = true;
        } catch Error(string memory reason) {
            dest.error = reason;
        } catch (bytes memory reason) {
            dest.error =
                string(abi.encodePacked("Deposit custom error: ", Strings.toHexString(uint32(bytes4(reason)), 4)));
        }

        if (dest.depositDone) {
            (,, uint availableBorrowsBase,,,) = IPool(pool).getUserAccountData(USER);
            LiquidationBotLib.ReserveData memory rd = LiquidationBotLib._getReserveData(ac, dest.borrowAsset);
            uint availableBorrows = LiquidationBotLib._fromBase(ac, rd, availableBorrowsBase);

            {
                IPool.ReserveData memory rdata = IPool(pool).getReserveData(dest.borrowAsset);
                uint availableLiquidity = IERC20(dest.borrowAsset).balanceOf(rdata.aTokenAddress);
                if (availableLiquidity < availableBorrows) {
                    _provideLiquidityToPool(ac, dest.borrowAsset, availableBorrows - availableLiquidity, dest);
                } else {
                    _removeExtraLiquidityFromPool(
                        ac, dest.collateralAsset, dest.borrowAsset, availableLiquidity - availableBorrows, dest
                    );
                }
            }

            // 2 = variable rate mode
            vm.prank(USER);
            try IPool(pool).borrow(dest.borrowAsset, availableBorrows * 99 / 100, 2, 0, USER) {
                dest.borrowDone = true;
            } catch Error(string memory reason) {
                dest.error = reason;
            } catch (bytes memory reason) {
                dest.error =
                    string(abi.encodePacked("Borrow custom error: ", Strings.toHexString(uint32(bytes4(reason)), 4)));
            }
        }

        (
            dest.userAccountData.totalCollateralBase,
            dest.userAccountData.totalDebtBase,
            dest.userAccountData.availableBorrowsBase,
            dest.userAccountData.currentLiquidationThreshold,
            dest.userAccountData.ltv,
            dest.userAccountData.healthFactor
        ) = IPool(pool).getUserAccountData(USER);

        return dest;
    }

    //endregion ---------------------- Internal logic

    //region ---------------------- Auxiliary functions

    function _provideLiquidityToPool(
        LiquidationBotLib.AaveContracts memory ac,
        address borrowAsset,
        uint amount,
        LendingPosition memory dest
    ) internal {
        deal(borrowAsset, OTHER_USER, amount);

        vm.prank(OTHER_USER);
        IERC20(borrowAsset).approve(address(ac.pool), amount);

        vm.prank(OTHER_USER);
        try ac.pool.supply(borrowAsset, amount, OTHER_USER, 0) {
            dest.providedBorrowLiquidity = amount;
        } catch Error(string memory reason) {
            dest.error = string(abi.encodePacked("Other user supply custom error: ", reason));
        } catch (bytes memory reason) {
            dest.error = string(
                abi.encodePacked("Other user supply custom error: ", Strings.toHexString(uint32(bytes4(reason)), 4))
            );
        }
    }

    /// @notice  borrow all liquidity to increase utilization (and make borrow APR > supply APR)
    function _removeExtraLiquidityFromPool(
        LiquidationBotLib.AaveContracts memory ac,
        address collateralAsset,
        address borrowAsset,
        uint amountToBorrow,
        LendingPosition memory dest
    ) internal {
        LiquidationBotLib.ReserveData memory rdb = LiquidationBotLib._getReserveData(ac, borrowAsset);
        LiquidationBotLib.ReserveData memory rdc = LiquidationBotLib._getReserveData(ac, collateralAsset);

        uint amountBorrowBase = LiquidationBotLib._toBase(ac, rdb, amountToBorrow);
        uint amountCollateralBase = amountBorrowBase * 10_000 / rdc.ltv;
        uint amountCollateral = LiquidationBotLib._fromBase(ac, rdc, amountCollateralBase);

        deal(collateralAsset, OTHER_USER, amountCollateral);

        vm.prank(OTHER_USER);
        IERC20(collateralAsset).approve(address(ac.pool), amountCollateral);

        vm.prank(OTHER_USER);
        try ac.pool.deposit(collateralAsset, amountCollateral, OTHER_USER, 0) {
            (,, uint availableBorrowsBase,,,) = ac.pool.getUserAccountData(OTHER_USER);

            uint amountToBorrowActual = LiquidationBotLib._fromBase(ac, rdb, availableBorrowsBase) * 99 / 100;

            vm.prank(OTHER_USER);
            try ac.pool.borrow(borrowAsset, amountToBorrowActual, 2, 0, OTHER_USER) {
                dest.borrowLiquidityRemoved = amountToBorrowActual;
            } catch Error(string memory reason) {
                dest.error = string(abi.encodePacked("Other user borrow custom error: ", reason));
            } catch (bytes memory reason) {
                dest.error = string(
                    abi.encodePacked("Other user borrow custom error: ", Strings.toHexString(uint32(bytes4(reason)), 4))
                );
            }
        } catch Error(string memory reason) {
            dest.error = string(abi.encodePacked("Other user deposit custom error: ", reason));
        } catch (bytes memory reason) {
            dest.error =
                string(abi.encodePacked("Other user deposit error: ", Strings.toHexString(uint32(bytes4(reason)), 4)));
        }
    }

    /// @notice Replace price oracle with mock that keeps prices fixed
    function _replacePriceOracle(LiquidationBotLib.AaveContracts memory ac) internal {
        IAaveAddressProvider addressProvider = IAaveAddressProvider(ac.pool.ADDRESSES_PROVIDER());

        IAavePriceOracle oracle = IAavePriceOracle(addressProvider.getPriceOracle());

        Aave3PriceOracleMock mockOracle = new Aave3PriceOracleMock(address(oracle));

        vm.prank(addressProvider.owner());
        addressProvider.setPriceOracle(address(mockOracle));
    }

    function saveToCsv(string memory fnOut, Results[] memory rr, ILiquidationBot bot) internal {
        (address flashLoanVault, uint flashLoanKind) = bot.getFlashLoanVault();
        string memory content = string(
            abi.encodePacked(
                "BlockNumber;",
                Strings.toString(selectedBlock),
                ";Indices: 0 - before liquidation, 1 - after liquidation;Price impact tolerance;",
                Strings.toString(bot.priceImpactTolerance()),
                ";Target health factor;",
                Strings.toString(bot.targetHealthFactor()),
                ";Flash loan vault;",
                Strings.toHexString(flashLoanVault),
                ";Flash loan kind;",
                Strings.toString(flashLoanKind),
                "\n"
            )
        );

        content = string(
            abi.encodePacked(
                content,
                "Pool;CollateralAsset;CollateralSymbol;BorrowAsset;BorrowSymbol;CollateralAmount;TotalCollateralBase0;TotalDebtBase0;HealthFactor0;currentLiquidationThreshold0;ltv0;ProvidedBorrowLiquidity;RemovedBorrowLiquidity;HealthFactorAfterForwardingTime;TotalCollateralBase1;TotalDebtBase1;HealthFactor1;currentLiquidationThreshold1;ltv1;BotProfitInBorrowAsset;DepositDone;BorrowDone;LiquidationDone;error\n"
            )
        );

        for (uint i = 0; i < rr.length; i++) {
            string memory line = string(
                abi.encodePacked(
                    Strings.toHexString(rr[i].pool),
                    ";",
                    Strings.toHexString(rr[i].position.collateralAsset),
                    ";",
                    IERC20Metadata(rr[i].position.collateralAsset).symbol(),
                    ";",
                    Strings.toHexString(rr[i].position.borrowAsset),
                    ";",
                    IERC20Metadata(rr[i].position.borrowAsset).symbol(),
                    ";"
                )
            );

            line = string(
                abi.encodePacked(
                    line,
                    Strings.toString(rr[i].position.collateralAmount),
                    ";",
                    Strings.toString(rr[i].position.userAccountData.totalCollateralBase),
                    ";",
                    Strings.toString(rr[i].position.userAccountData.totalDebtBase),
                    ";",
                    Strings.toString(rr[i].position.userAccountData.healthFactor),
                    ";",
                    Strings.toString(rr[i].position.userAccountData.currentLiquidationThreshold),
                    ";",
                    Strings.toString(rr[i].position.userAccountData.ltv),
                    ";"
                )
            );

            line = string(
                abi.encodePacked(
                    line,
                    Strings.toString(rr[i].position.providedBorrowLiquidity),
                    ";",
                    Strings.toString(rr[i].position.borrowLiquidityRemoved),
                    ";",
                    Strings.toString(rr[i].healthFactorAfterForwardingTime),
                    ";",
                    Strings.toString(rr[i].userAccountData.totalCollateralBase),
                    ";",
                    Strings.toString(rr[i].userAccountData.totalDebtBase),
                    ";",
                    Strings.toString(rr[i].userAccountData.healthFactor),
                    ";",
                    Strings.toString(rr[i].userAccountData.currentLiquidationThreshold),
                    ";"
                )
            );

            line = string(
                abi.encodePacked(
                    line,
                    Strings.toString(rr[i].userAccountData.ltv),
                    ";",
                    Strings.toString(rr[i].botProfitInBorrowAsset),
                    ";",
                    rr[i].position.depositDone ? "1;" : "0;",
                    rr[i].position.borrowDone ? "1;" : "0;",
                    rr[i].liquidationDone ? "1;" : "0;",
                    string(
                        abi.encodePacked(bytes(rr[i].position.error).length > 0 ? rr[i].position.error : rr[i].error)
                    ),
                    ";",
                    "\n"
                )
            );

            content = string(abi.encodePacked(content, line));
        }

        if (!vm.exists("./tmp")) {
            vm.createDir("./tmp", true);
        }
        vm.writeFile(string.concat("./tmp/", fnOut), content);
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
    /// @notice Create and set up liquidation bot instance. TODO: use deployed bot with actual config later
    function _getBotInstance() internal returns (ILiquidationBot) {
        ILiquidationBot bot = _createLiquidationBotInstance();
        _setUpLiquidationBot(
            bot,
            SonicConstantsLib.BEETS_VAULT_V3,
            uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1),
            TARGET_HEALTH_FACTOR_18
        );
        _addAdapter();
        _addRoutes();

        return bot;
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
        IPriceReader priceReader = IPriceReader(IPlatform(SonicConstantsLib.PLATFORM).priceReader());
        multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();

        vm.prank(multisig);
        priceReader.addAdapter(address(proxy));

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
