// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm, Test} from "forge-std/Test.sol";
import {BrunchAdapter} from "../../src/adapters/BrunchAdapter.sol";
import {Aave3PriceOracleMock} from "../../src/test/Aave3PriceOracleMock.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IAaveAddressProvider} from "../../src/integrations/aave/IAaveAddressProvider.sol";
import {IAaveDataProvider} from "../../src/integrations/aave/IAaveDataProvider.sol";
import {IAavePoolConfigurator} from "../../src/integrations/aave/IAavePoolConfigurator.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";
import {IAToken} from "../../src/integrations/aave/IAToken.sol";
import {IAavePriceOracle} from "../../src/integrations/aave/IAavePriceOracle.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {ILiquidationBot} from "../../src/interfaces/ILiquidationBot.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {LiquidationBotLib} from "../../src/periphery/libs/LiquidationBotLib.sol";
import {LiquidationBot} from "../../src/periphery/LiquidationBot.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {AlgebraV4Adapter, AmmAdapterIdLib} from "../../src/adapters/AlgebraV4Adapter.sol";
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

    // todo
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
        uint totalCollateralBase;
        uint totalDebtBase;
        uint healthFactor;

        bool depositDone;
        bool borrowDone;

        uint providedBorrowLiquidity;
    }

    struct Results {
        LendingPosition position;
        uint healthFactorAfterForwardingTime;
        uint healthFactorAfterLiquidation;
        uint botProfitInBorrowAsset;

        bool liquidationDone;
    }

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

        _addAdapter(); // todo
        _addRoutes(); // todo
    }

    function testLiquidationBatch() public {
        address[2] memory pools = [
            SonicConstantsLib.STABILITY_USD_MARKET_GEN2_POOL,
            SonicConstantsLib.BRUNCH_GEN2_POOL
        ];

        Results[] memory rets = new Results[](pools.length);
        for (uint i = 0; i < pools.length; i++) {
            uint snapshot = vm.snapshotState();
            rets[i] = _testLiquidation(pools[i]);
            vm.revertToState(snapshot);
            console.log("Liquidation in pool was done:", i, pools[i]);
        }

        saveToCsv("Lending.Batch.Sonic.results.csv", rets);
    }

    function testSingleLiquidation() public {
        _testLiquidation(SonicConstantsLib.BRUNCH_GEN2_POOL);
    }

    //region ---------------------- Internal logic
    function _testLiquidation(address pool) internal returns (Results memory ret) {
        LiquidationBotLib.AaveContracts memory ac = LiquidationBotLib.getAaveContracts(pool);

        // ----------------- create lending position
        ret.position = _createLendingPosition(ac, pool, 100);
        // console.log(ret.position.totalCollateralBase, ret.position.totalDebtBase, ret.position.healthFactor);

        // ----------------- replace price oracle to fix prices life time
        _replacePriceOracle(ac);

        // ----------------- move time until health factor < 1
        for (uint i; i < 256; ++i) {
            (, , , , , ret.healthFactorAfterForwardingTime) = IPool(pool).getUserAccountData(USER);
            if (ret.healthFactorAfterForwardingTime < 1e18) break;

            vm.warp(block.timestamp + 1 * 7 * 24 * 3600);
        }

        if (ret.healthFactorAfterForwardingTime < 1e18) {
            // ----------------- make liquidation

            ILiquidationBot bot = _createLiquidationBotInstance();
            _setUpLiquidationBot(bot, SonicConstantsLib.BEETS_VAULT_V3, uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1));

            address[] memory users = new address[](1);
            users[0] = USER;

            try bot.liquidate(pool, users) {
                ret.liquidationDone = true;
            } catch {}
        }

        ret.botProfitInBorrowAsset = IERC20(ret.position.borrowAsset).balanceOf(PROFIT_TARGET);
        (, , , , , ret.healthFactorAfterLiquidation) = IPool(pool).getUserAccountData(USER);

        return ret;
    }

    function _createLiquidationBotInstance() internal returns (ILiquidationBot) {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new LiquidationBot()));

        ILiquidationBot bot = ILiquidationBot(address(proxy));
        bot.initialize(SonicConstantsLib.PLATFORM);

        return bot;
    }

    function _setUpLiquidationBot(ILiquidationBot bot, address flashLoanVault, uint flashLoanKind) internal {
        vm.prank(multisig);
        bot.changeWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, true);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSD).changeWhitelist(address(bot), true);

        vm.prank(multisig);
        bot.setTargetHealthFactor(0);

        vm.prank(multisig);
        bot.setProfitTarget(PROFIT_TARGET);

        vm.prank(multisig);
        bot.setFlashLoanVault(flashLoanVault, flashLoanKind);

        vm.prank(multisig);
        bot.changeWhitelist(address(this), true);
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

    function _getAssets(LiquidationBotLib.AaveContracts memory ac) internal view returns (address collateralAsset, address borrowAsset) {
        IAaveDataProvider.TokenData[] memory assets = ac.dataProvider.getAllReservesTokens();
        for (uint i; i < assets.length; ++i) {
            (, , , , , bool usageAsCollateralEnabled, bool borrowingEnabled, , , ) = ac.dataProvider.getReserveConfigurationData(assets[i].tokenAddress);
            if (usageAsCollateralEnabled && !borrowingEnabled) {
                collateralAsset = assets[i].tokenAddress;
            } else if (!usageAsCollateralEnabled && borrowingEnabled) {
                borrowAsset = assets[i].tokenAddress;
            }
        }

        return (collateralAsset, borrowAsset);
    }

    function _createLendingPosition(LiquidationBotLib.AaveContracts memory ac, address pool, uint amountNoDecimal) internal returns (LendingPosition memory dest) {
        (dest.collateralAsset, dest.borrowAsset) = _getAssets(ac);
        uint amount = _getDefaultAmountToDeposit(dest.collateralAsset, amountNoDecimal);

        deal(dest.collateralAsset, USER, amount);

        vm.prank(USER);
        IERC20(dest.collateralAsset).approve(pool, amount);

        vm.prank(USER);
        try IPool(pool).deposit(dest.collateralAsset, amount, USER, 0) {
            dest.collateralAmount = amount;
            dest.depositDone = true;
        } catch {}

        if (dest.depositDone) {
            (, , uint availableBorrowsBase, , , ) = IPool(pool).getUserAccountData(USER);
            LiquidationBotLib.ReserveData memory rd = LiquidationBotLib._getReserveData(ac, dest.borrowAsset);
            uint availableBorrows = LiquidationBotLib._fromBase(ac, rd, availableBorrowsBase);

            {
                IPool.ReserveData memory rdata = IPool(pool).getReserveData(dest.borrowAsset);
                uint availableLiquidity = IERC20(dest.borrowAsset).balanceOf(rdata.aTokenAddress);
                if (availableLiquidity < availableBorrows) {
                    dest.providedBorrowLiquidity = availableBorrows - availableLiquidity;
                    _provideLiquidityToPool(ac, dest.borrowAsset, dest.providedBorrowLiquidity);
                } else {
                    // TODO: borrow all liquidity to increase utilization (and make borrow APR > supply APR)
                }
            }

            // 2 = variable rate mode
            vm.prank(USER);
            try IPool(pool).borrow(dest.borrowAsset, availableBorrows * 99 / 100, 2, 0, USER) {
                dest.borrowDone = true;
            } catch {}

        }
        (dest.totalCollateralBase, dest.totalDebtBase, , , , dest.healthFactor) = IPool(pool).getUserAccountData(USER);

        return dest;
    }

    function _provideLiquidityToPool(LiquidationBotLib.AaveContracts memory ac, address borrowAsset, uint amount) internal {
        deal(borrowAsset, OTHER_USER, amount);

        vm.prank(OTHER_USER);
        IERC20(borrowAsset).approve(address(ac.pool), amount);

        vm.prank(OTHER_USER);
        ac.pool.supply(borrowAsset, amount, OTHER_USER, 0);
    }

    function _replacePriceOracle(LiquidationBotLib.AaveContracts memory ac) internal {
        IAaveAddressProvider addressProvider = IAaveAddressProvider(ac.pool.ADDRESSES_PROVIDER());

        IAavePriceOracle oracle = IAavePriceOracle(addressProvider.getPriceOracle());

        Aave3PriceOracleMock mockOracle = new Aave3PriceOracleMock(address(oracle));

        vm.prank(addressProvider.owner());
        addressProvider.setPriceOracle(address(mockOracle));
    }

    //endregion ---------------------- Internal logic

    //region ---------------------- Auxiliary functions
    function saveToCsv(string memory fnOut, Results[] memory rr) internal {
        string memory content = string(abi.encodePacked("BlockNumber;", Strings.toString(selectedBlock), "\n"));

        content = string(
            abi.encodePacked(
                content,
                "CollateralAsset;BorrowAsset;CollateralAmount;TotalCollateralBase;TotalDebtBase;HealthFactor;DepositDone;BorrowDone;ProvidedBorrowLiquidity;HealthFactorAfterForwardingTime;HealthFactorAfterLiquidation;BotProfitInBorrowAsset;LiquidationDone\n"
            )
        );

        for (uint i = 0; i < rr.length; i++) {
            string memory line = string(
                abi.encodePacked(
                    Strings.toHexString(rr[i].position.collateralAsset), ";",
                    Strings.toHexString(rr[i].position.borrowAsset), ";",
                    Strings.toString(rr[i].position.collateralAmount), ";",
                    Strings.toString(rr[i].position.totalCollateralBase), ";",
                    Strings.toString(rr[i].position.totalDebtBase), ";",
                    Strings.toString(rr[i].position.healthFactor), ";"
                )
            );

            line = string(
                abi.encodePacked(
                    line,
                    rr[i].position.depositDone ? "1;" : "0;",
                    rr[i].position.borrowDone ? "1;" : "0;",
                    Strings.toString(rr[i].position.providedBorrowLiquidity), ";",
                    Strings.toString(rr[i].healthFactorAfterForwardingTime), ";",
                    Strings.toString(rr[i].healthFactorAfterLiquidation), ";",
                    Strings.toString(rr[i].botProfitInBorrowAsset), ";",
                    rr[i].liquidationDone ? "1" : "0",
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

    /// @notice Deal doesn't work with aave tokens. So, deal the asset and mint aTokens instead.
    /// @dev https://github.com/foundry-rs/forge-std/issues/140
    function _dealAave(address aToken_, address to, uint amount) internal {
        IPool pool = IPool(IAToken(aToken_).POOL());

        address asset = IAToken(aToken_).UNDERLYING_ASSET_ADDRESS();

        deal(asset, to, amount);

        vm.prank(to);
        IERC20(asset).approve(address(pool), amount);

        vm.prank(to);
        pool.deposit(asset, amount, to, 0);
    }

    //endregion ---------------------- Auxiliary functions

    //region ---------------------- Sonic-related functions
    function _getDefaultAmountToDeposit(address asset_, uint amountNoDecimals) internal view returns (uint) {
        return amountNoDecimals * 10 ** IERC20Metadata(asset_).decimals();
    }

    //endregion ---------------------- Sonic-related functions
}
