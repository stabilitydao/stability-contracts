// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {console, Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ChainSetup} from "./ChainSetup.sol";
import {Utils} from "./Utils.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {StrategyDeveloperLib} from "../../src/strategies/libs/StrategyDeveloperLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {StrategyLib} from "../../src/strategies/libs/StrategyLib.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {ILPStrategy} from "../../src/interfaces/ILPStrategy.sol";
import {IStrategyLogic} from "../../src/interfaces/IStrategyLogic.sol";
import {IVault, IStabilityVault} from "../../src/interfaces/IVault.sol";
import {IVaultManager} from "../../src/interfaces/IVaultManager.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {IHardWorker} from "../../src/interfaces/IHardWorker.sol";
import {IZap} from "../../src/interfaces/IZap.sol";
import {IALM} from "../../src/interfaces/IALM.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {IUniswapV3Pool} from "../../src/integrations/uniswapv3/IUniswapV3Pool.sol";

abstract contract UniversalTest is Test, ChainSetup, Utils {
    Strategy[] public strategies;
    string public strategyId;
    address internal currentStrategy;
    uint[] public specialDepositAmounts;
    uint public duration1 = 6 hours;
    uint public duration2 = 3 hours;
    uint public duration3 = 3 hours;
    uint public depositedSharesCheckDelimiter = 1000;
    bool public makePoolVolume = true;
    uint public makePoolVolumePriceImpactTolerance = 6_000;
    bool public allowZeroApr = false;
    uint public poolVolumeSwapAmount0Multiplier = 2;
    uint public poolVolumeSwapAmount1Multiplier = 2;
    mapping(address pool => uint multiplier) public poolVolumeSwapAmount0MultiplierForPool;
    mapping(address pool => uint multiplier) public poolVolumeSwapAmount1MultiplierForPool;

    struct Strategy {
        string id;
        address pool;
        uint farmId;
        address[] strategyInitAddresses;
        uint[] strategyInitNums;
    }

    struct TestStrategiesVars {
        bool isLPStrategy;
        address strategyLogic;
        address strategyImplementation;
        bool farming;
        uint tokenId;
        string[] types;
        IHardWorker hardWorker;
        address vault;
        address[] vaultsForHardWork;
        uint apr;
        uint aprCompound;
        uint earned;
        uint duration;
        Vm.Log[] entries;
        address ammAdapter;
        address pool;
        bool hwEventFound;
        uint depositUsdValue;
        uint withdrawnUsdValue;
        bool isALM;
        bool isLeverageLending;
    }

    modifier universalTest() {
        _init();
        _;
        _testStrategies();
    }

    function _addRewards(uint farmId) internal virtual {}

    function _preHardWork() internal virtual {}

    function _rebalance() internal virtual {}

    function _preHardWork(uint farmId) internal virtual {}

    function _preDeposit() internal virtual {}

    function _skip(uint time, uint) internal virtual {
        skip(time);
    }

    function testNull() public {}

    function _testStrategies() internal {
        console.log(string.concat("Universal test of strategy logic", strategyId));
        TestStrategiesVars memory vars;
        vars.hardWorker = IHardWorker(platform.hardWorker());
        vm.startPrank(platform.governance());
        vars.hardWorker.setDedicatedServerMsgSender(address(this), true);
        vm.expectRevert(abi.encodeWithSelector(IControllable.AlreadyExist.selector));
        vars.hardWorker.setDedicatedServerMsgSender(address(this), true);
        vm.stopPrank();
        vars.vaultsForHardWork = new address[](1);
        vars.strategyLogic = platform.strategyLogic();
        for (uint i; i < strategies.length; ++i) {
            assertNotEq(
                StrategyDeveloperLib.getDeveloper(strategies[i].id),
                address(0),
                "Universal test: put your address to StrategyDeveloperLib"
            );
            IFactory.StrategyLogicConfig memory strategyConfig =
                factory.strategyLogicConfig(keccak256(bytes(strategies[i].id)));
            // (,vars.strategyImplementation,,,vars.farming, vars.tokenId) = factory.strategyLogicConfig(keccak256(bytes(strategies[i].id)));
            (vars.strategyImplementation, vars.farming, vars.tokenId) =
                (strategyConfig.implementation, strategyConfig.farming, strategyConfig.tokenId);
            assertNotEq(
                vars.strategyImplementation, address(0), "Strategy implementation not found. Put it to chain lib."
            );
            writeNftSvgToFile(
                vars.strategyLogic, vars.tokenId, string.concat("out/StrategyLogic_", strategies[i].id, ".svg")
            );
            assertEq(IStrategyLogic(vars.strategyLogic).tokenStrategyLogic(vars.tokenId), strategies[i].id);
            vars.types = IStrategy(vars.strategyImplementation).supportedVaultTypes();

            for (uint k; k < vars.types.length; ++k) {
                /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                /*                       CREATE VAULT                         */
                /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

                {
                    address[] memory vaultInitAddresses = new address[](0);
                    uint[] memory vaultInitNums = new uint[](0);

                    address[] memory initStrategyAddresses;
                    uint[] memory nums;
                    int24[] memory ticks = new int24[](0);

                    if (vars.farming) {
                        nums = new uint[](1);
                        nums[0] = strategies[i].farmId;

                        // test bad params
                        initStrategyAddresses = new address[](1);
                        vm.expectRevert(IControllable.IncorrectInitParams.selector);
                        factory.deployVaultAndStrategy(
                            vars.types[k],
                            strategies[i].id,
                            vaultInitAddresses,
                            vaultInitNums,
                            initStrategyAddresses,
                            nums,
                            ticks
                        );
                        initStrategyAddresses = new address[](0);

                        IFactory.Farm memory f = factory.farm(nums[0]);
                        int24[] memory goodTicks = f.ticks;
                        f.ticks = new int24[](1000);
                        factory.updateFarm(nums[0], f);
                        vm.expectRevert(IFarmingStrategy.BadFarm.selector);
                        factory.deployVaultAndStrategy(
                            vars.types[k],
                            strategies[i].id,
                            vaultInitAddresses,
                            vaultInitNums,
                            initStrategyAddresses,
                            nums,
                            ticks
                        );
                        f.ticks = goodTicks;

                        string memory goodStrategyId = f.strategyLogicId;
                        f.strategyLogicId = "INCORRECT ID";
                        factory.updateFarm(nums[0], f);
                        vm.expectRevert(IFarmingStrategy.IncorrectStrategyId.selector);
                        factory.deployVaultAndStrategy(
                            vars.types[k],
                            strategies[i].id,
                            vaultInitAddresses,
                            vaultInitNums,
                            initStrategyAddresses,
                            nums,
                            ticks
                        );

                        f.strategyLogicId = goodStrategyId;

                        factory.updateFarm(nums[0], f);
                        ///
                    } else {
                        initStrategyAddresses = new address[](10);
                        vm.expectRevert(IControllable.IncorrectInitParams.selector);
                        factory.deployVaultAndStrategy(
                            vars.types[k],
                            strategies[i].id,
                            vaultInitAddresses,
                            vaultInitNums,
                            initStrategyAddresses,
                            nums,
                            ticks
                        );

                        initStrategyAddresses = strategies[i].strategyInitAddresses;
                        nums = strategies[i].strategyInitNums;
                    }

                    factory.deployVaultAndStrategy(
                        vars.types[k],
                        strategies[i].id,
                        vaultInitAddresses,
                        vaultInitNums,
                        initStrategyAddresses,
                        nums,
                        ticks
                    );

                    uint vaultTokenId = factory.deployedVaultsLength() - 1;
                    assertEq(IERC721(platform.vaultManager()).ownerOf(vaultTokenId), address(this));
                    IVaultManager(platform.vaultManager()).setRevenueReceiver(vaultTokenId, address(1));
                }

                vars.vault = factory.deployedVault(factory.deployedVaultsLength() - 1);
                assertEq(
                    IVaultManager(platform.vaultManager()).tokenVault(factory.deployedVaultsLength() - 1), vars.vault
                );
                vars.vaultsForHardWork[0] = vars.vault;
                IStrategy strategy = IVault(vars.vault).strategy();
                currentStrategy = address(strategy);
                strategy.getSpecificName();
                strategy.lastAprCompound();
                address[] memory assets = strategy.assets();
                assertGt(assets.length, 0, "UniversalTest: assets length is zero");
                vars.isLPStrategy = IERC165(address(strategy)).supportsInterface(type(ILPStrategy).interfaceId);
                if (vars.isLPStrategy) {
                    vars.ammAdapter = address(ILPStrategy(address(strategy)).ammAdapter());
                    assertEq(IAmmAdapter(vars.ammAdapter).ammAdapterId(), ILPStrategy(address(strategy)).ammAdapterId());
                    vars.pool = ILPStrategy(address(strategy)).pool();
                }
                vars.isALM = IERC165(address(strategy)).supportsInterface(type(IALM).interfaceId);
                vars.isLeverageLending =
                    IERC165(address(strategy)).supportsInterface(type(ILeverageLendingStrategy).interfaceId);

                console.log(
                    string.concat(
                        IERC20Metadata(vars.vault).symbol(),
                        " [Compound ratio: 100%]. Name: ",
                        IERC20Metadata(vars.vault).name(),
                        ". Strategy: ",
                        strategy.description()
                    )
                );

                if (vars.farming) {
                    assertEq(IFarmingStrategy(address(strategy)).canFarm(), true);
                    IFarmingStrategy(address(strategy)).farmId();
                    IFarmingStrategy(address(strategy)).stakingPool();
                }

                {
                    uint[] memory assetsProportions = IStrategy(address(strategy)).getAssetsProportions();
                    bool isZero = true;
                    for (uint x; x < assetsProportions.length; x++) {
                        if (assetsProportions[x] != 0) {
                            isZero = false;
                            break;
                        }
                    }
                    assertEq(isZero, false, "Assets proportions are zero");
                }

                /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                /*                          DEPOSIT                           */
                /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

                (uint tvl,) = IVault(vars.vault).tvl();
                strategy.assetsAmounts();

                _preDeposit();

                // get amounts for deposit
                uint[] memory depositAmounts = new uint[](assets.length);
                for (uint j; j < assets.length; ++j) {
                    (uint price,) = IPriceReader(platform.priceReader()).getPrice(assets[j]);

                    // console.log("!!!!", assets[j]);
                    require(price > 0, "UniversalTest: price is zero. Forget to add swapper routes?");
                    depositAmounts[j] = 1000 * 10 ** IERC20Metadata(assets[j]).decimals() * 1e18 / price;
                }

                if (vars.isALM && makePoolVolume) {
                    IUniswapV3Pool(vars.pool).increaseObservationCardinalityNext(100);
                    _makePoolVolume(vars.pool, vars.ammAdapter, assets, depositAmounts[0], 100);
                    IERC20(assets[0]).approve(vars.vault, depositAmounts[0]);
                    IERC20(assets[1]).approve(vars.vault, depositAmounts[1]);
                    vm.expectRevert();
                    IVault(vars.vault).depositAssets(assets, depositAmounts, 0, address(0));
                    skip(600);
                    // cover
                    IALM(address(strategy)).setupPriceChangeProtection(true, 600, 10_000);
                }

                // deal and approve
                for (uint j; j < assets.length; ++j) {
                    _deal(assets[j], address(this), depositAmounts[j]);
                    IERC20(assets[j]).approve(vars.vault, depositAmounts[j]);
                }

                // deposit
                IVault(vars.vault).depositAssets(assets, depositAmounts, 0, address(0));
                (tvl,) = IVault(vars.vault).tvl();
                assertGt(tvl, 0, "Universal test: tvl is zero");

                _skip(duration1, strategies[i].farmId);

                if (vars.isLPStrategy && makePoolVolume) {
                    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                    /*                       MAKE POOL VOLUME                     */
                    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
                    _makePoolVolume(vars.pool, vars.ammAdapter, assets, depositAmounts[0], depositAmounts[1]);
                }

                /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                /*                       SPECIAL DEPOSIT                      */
                /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
                {
                    if (specialDepositAmounts.length > 0) {
                        require(
                            specialDepositAmounts.length == assets.length, "UT: specialDepositAmounts length mismatch"
                        );
                        for (uint j; j < assets.length; ++j) {
                            IERC20(assets[j]).approve(vars.vault, specialDepositAmounts[j]);
                            _deal(assets[j], address(this), specialDepositAmounts[j]);
                        }
                        IVault(vars.vault).depositAssets(assets, specialDepositAmounts, 0, address(0));
                    }
                }

                /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                /*                       SMALL WITHDRAW                       */
                /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

                _skip(duration2, strategies[i].farmId);

                vm.roll(block.number + 6);

                {
                    uint[] memory withdrewAssets = IVault(vars.vault).withdrawAssets(
                        assets, IERC20(vars.vault).balanceOf(address(this)) / 1000, new uint[](assets.length)
                    );
                    assertEq(withdrewAssets.length, assets.length, "Withdraw assets length mismatch");

                    bool isEmpty = true;
                    for (uint j; j < assets.length; ++j) {
                        if (withdrewAssets[j] != 0) {
                            isEmpty = false;
                            break;
                        }
                    }
                    assertEq(isEmpty, false, "Withdraw assets zero amount");
                }

                /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                /*             MAX DEPOSIT, MAX WITHDRAW, POOL TVL            */
                /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
                assertEq(_checkMaxWithdraw(), true, "maxWithdraw test is passed");
                assertEq(_checkMaxDeposit(), true, "maxDeposit test is passed");
                assertEq(_checkPoolTvl(), true, "poolTvl test is passed");

                if (vars.isLPStrategy && makePoolVolume) {
                    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                    /*                       MAKE POOL VOLUME                     */
                    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
                    {
                        uint multiplier0 = poolVolumeSwapAmount0MultiplierForPool[vars.pool] != 0
                            ? poolVolumeSwapAmount0MultiplierForPool[vars.pool]
                            : poolVolumeSwapAmount0Multiplier;
                        uint multiplier1 = poolVolumeSwapAmount1MultiplierForPool[vars.pool] != 0
                            ? poolVolumeSwapAmount1MultiplierForPool[vars.pool]
                            : poolVolumeSwapAmount1Multiplier;
                        _makePoolVolume(
                            vars.pool,
                            vars.ammAdapter,
                            assets,
                            depositAmounts[0] * multiplier0,
                            depositAmounts[1] * multiplier1
                        );
                    }
                }

                _preHardWork();
                _preHardWork(strategies[i].farmId);

                _skip(duration3, strategies[i].farmId);
                vm.roll(block.number + 6);

                // check not claimed revenue if available
                {
                    (address[] memory __assets, uint[] memory amounts) = strategy.getRevenue();
                    if (__assets.length > 0) {
                        (uint totalRevenueUSD,,,) =
                            IPriceReader(platform.priceReader()).getAssetsPrice(__assets, amounts);
                        assertGt(totalRevenueUSD, 0, "Universal test: estimated totalRevenueUSD is zero");
                        assertGt(__assets.length, 0, "Universal test: getRevenue assets length is zero");
                        if (totalRevenueUSD == 0) {
                            for (uint x; x < __assets.length; ++x) {
                                console.log(
                                    string.concat("__assets[", Strings.toString(x), "]:"),
                                    IERC20Metadata(__assets[x]).symbol()
                                );
                                console.log(string.concat(" amounts[", Strings.toString(x), "]:"), amounts[x]);
                            }
                        }
                    }
                }

                /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                /*                         HARDWORK 0                         */
                /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
                assertEq(strategy.isReadyForHardWork(), true, "Not ready for HardWork");
                vm.txGasPrice(15e10); // 150gwei
                {
                    vars.apr = 0;
                    vars.aprCompound = 0;
                    vars.earned = 0;
                    vars.duration = 0;
                    vm.recordLogs();
                    /// forge-lint: disable-next-line
                    vars.hardWorker.call(vars.vaultsForHardWork);
                    vars.entries = vm.getRecordedLogs();
                    vars.hwEventFound = false;
                    for (uint j = 0; j < vars.entries.length; ++j) {
                        if (
                            vars.entries[j].topics[0]
                                == keccak256("HardWork(uint256,uint256,uint256,uint256,uint256,uint256,uint256[])")
                        ) {
                            vars.hwEventFound = true;
                            (uint tempApr, uint tempAprCompound, uint tempEarned, uint tempTvl, uint tempDuration) =
                                abi.decode(vars.entries[j].data, (uint, uint, uint, uint, uint));

                            vars.apr = tempApr;
                            vars.aprCompound = tempAprCompound;
                            vars.earned = tempEarned;
                            tvl = tempTvl;
                            vars.duration = tempDuration;

                            console.log(
                                string.concat(
                                    "    APR: ",
                                    CommonLib.formatApr(tempApr),
                                    ". APR compound: ",
                                    CommonLib.formatApr(tempAprCompound),
                                    ". Earned: ",
                                    CommonLib.formatUsdAmount(tempEarned),
                                    ". TVL: ",
                                    CommonLib.formatUsdAmount(tempTvl),
                                    ". Duration: ",
                                    Strings.toString(tempDuration),
                                    "."
                                )
                            );

                            StrategyLib.computeApr(tempTvl, tempEarned, tempDuration);

                            if (!allowZeroApr) {
                                assertGt(tempApr, 0, "HardWork APR");
                                assertGt(tempEarned, 0, "HardWork Earned");
                            }

                            assertGt(tempTvl, 0, "HardWork TVL");
                            assertGt(tempDuration, 0, "HardWork duration");
                            if (!allowZeroApr) {
                                assertGt(tempAprCompound, 0, "Hardwork APR compound is zero. Check _compound() method.");
                            }
                        }

                        if (
                            vars.entries[j].topics[0]
                                == keccak256(
                                    "LeverageLendingHardWork(int256,int256,uint256,uint256,uint256,uint256,uint256)"
                                )
                        ) {
                            (
                                int realApr,
                                int earned,
                                uint realTvl,
                                ,
                                uint realSharePrice,
                                uint supplyApr,
                                uint borrowApr
                            ) = abi.decode(vars.entries[j].data, (int, int, uint, uint, uint, uint, uint));
                            (uint ltv,, uint leverage,,,) = ILeverageLendingStrategy(address(strategy)).health();

                            console.log(
                                string.concat(
                                    "    Real APR: ",
                                    CommonLib.formatAprInt(realApr),
                                    ". Earned: ",
                                    CommonLib.i2s2(earned),
                                    ". Real TVL: ",
                                    CommonLib.formatUsdAmount(realTvl),
                                    ". Real share price: ",
                                    _formatSharePrice(realSharePrice),
                                    ". LTV: ",
                                    _formatLtv(ltv),
                                    ". Leverage: ",
                                    _formatLeverage(leverage),
                                    ". Supply APR: ",
                                    CommonLib.formatApr(supplyApr),
                                    ". Borrow APR: ",
                                    CommonLib.formatApr(borrowApr),
                                    "."
                                )
                            );
                        }
                    }
                    require(vars.hwEventFound, "UniversalTest: HardWork event not emitted");
                }

                if (vars.isLeverageLending) {
                    // decrease LTV
                    (uint ltv,, uint leverage,,,) = ILeverageLendingStrategy(address(strategy)).health();
                    uint rebalanceDebtTarget = ltv - 10_00;
                    ILeverageLendingStrategy(address(strategy)).rebalanceDebt(rebalanceDebtTarget, 0); // 0 = minSharePrice
                    (ltv,, leverage,,,) = ILeverageLendingStrategy(address(strategy)).health();
                    console.log(
                        string.concat(
                            "Re-balance debt LTV target: ",
                            _formatLtv(rebalanceDebtTarget),
                            ". Result LTV: ",
                            _formatLtv(ltv),
                            ". Leverage: ",
                            _formatLeverage(leverage),
                            "."
                        )
                    );
                    // increase LTV
                    rebalanceDebtTarget = ltv + 10_00;
                    ILeverageLendingStrategy(address(strategy)).rebalanceDebt(rebalanceDebtTarget, 0); // 0 = minSharePrice
                    (ltv,, leverage,,,) = ILeverageLendingStrategy(address(strategy)).health();
                    console.log(
                        string.concat(
                            "Re-balance debt LTV target: ",
                            _formatLtv(rebalanceDebtTarget),
                            ". Result LTV: ",
                            _formatLtv(ltv),
                            ". Leverage: ",
                            _formatLeverage(leverage),
                            "."
                        )
                    );

                    ILeverageLendingStrategy(address(strategy)).setTargetLeveragePercent(86_99);
                    ILeverageLendingStrategy(address(strategy)).getSupplyAndBorrowAprs();
                }

                /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                /*                  NO EMPTY HARDWORKS                        */
                /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
                if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.DEFIEDGE_QUICKSWAP_MERKL_FARM)) {
                    vm.startPrank(address(vars.hardWorker));
                    vm.expectRevert(abi.encodeWithSelector(IStrategy.NotReadyForHardWork.selector));
                    IVault(vars.vault).doHardWork();
                    vm.stopPrank();
                }

                /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                /*                      ADD REWARDS                           */
                /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
                _addRewards(strategies[i].farmId);

                /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                /*                        WITHDRAW ALL                        */
                /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
                uint totalWas = strategy.total();
                vm.roll(block.number + 6);
                IVault(vars.vault).withdrawAssets(
                    assets, IERC20(vars.vault).balanceOf(address(this)), new uint[](assets.length)
                );

                /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                /*       UNDERLYING DEPOSIT, WITHDRAW. HARDWORK ON DEPOSIT    */
                /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
                if (
                    !CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.TRIDENT_PEARL_FARM)
                        || strategies[i].farmId == 0
                ) {
                    address underlying = strategy.underlying();
                    if (underlying != address(0)) {
                        address tempVault = vars.vault;
                        address[] memory underlyingAssets = new address[](1);
                        underlyingAssets[0] = underlying;
                        uint[] memory underlyingAmounts = new uint[](1);

                        // first other user need to deposit to not hold vault only with dead shares
                        underlyingAmounts[0] = totalWas / 100;
                        _dealUnderlying(underlying, address(100), underlyingAmounts[0]);
                        vm.startPrank(address(100));
                        IERC20(underlying).approve(tempVault, underlyingAmounts[0]);
                        IVault(tempVault).depositAssets(underlyingAssets, underlyingAmounts, 0, address(100));
                        vm.stopPrank();

                        _skip(7200, strategies[i].farmId);

                        bool wasReadyForHardWork = strategy.isReadyForHardWork();

                        _dealUnderlying(underlying, address(this), totalWas);
                        // Following check was moved inside _dealUnderlying because of problems on avalanche
                        // assertEq(IERC20(underlying).balanceOf(address(this)), totalWas, "U1");
                        IERC20(underlying).approve(tempVault, totalWas);

                        underlyingAmounts[0] = totalWas;
                        (, uint sharesOut, uint valueOut) =
                            IVault(tempVault).previewDepositAssets(underlyingAssets, underlyingAmounts);
                        assertEq(valueOut, totalWas, "previewDepositAssets by underlying valueOut");
                        uint lastHw = strategy.lastHardWork();
                        IVault(tempVault).depositAssets(underlyingAssets, underlyingAmounts, 0, address(0));
                        if (strategy.isHardWorkOnDepositAllowed() && wasReadyForHardWork) {
                            assertGt(strategy.lastHardWork(), lastHw, "HardWork not happened");
                            assertGt(strategy.total(), totalWas, "Strategy total not increased after HardWork");
                        }

                        assertEq(IERC20(underlying).balanceOf(address(this)), 0);

                        uint vaultBalance = IERC20(tempVault).balanceOf(address(this));
                        if (!strategy.isHardWorkOnDepositAllowed()) {
                            assertEq(
                                vaultBalance,
                                sharesOut,
                                "previewDepositAssets by underlying: sharesOut and real shares after deposit mismatch"
                            );
                        } else {
                            assertLt(
                                vaultBalance,
                                sharesOut + sharesOut / depositedSharesCheckDelimiter,
                                "previewDepositAssets by underlying: vault balance too big"
                            );
                            assertGt(
                                vaultBalance,
                                sharesOut - sharesOut / depositedSharesCheckDelimiter,
                                "previewDepositAssets by underlying: vault balance too small"
                            );
                        }

                        uint[] memory minAmounts = new uint[](1);
                        minAmounts[0] = totalWas - totalWas / 10000;
                        vm.expectRevert(abi.encodeWithSelector(IStabilityVault.WaitAFewBlocks.selector));
                        IVault(tempVault).withdrawAssets(underlyingAssets, vaultBalance, minAmounts);
                        vm.roll(block.number + 6);
                        IVault(tempVault).withdrawAssets(underlyingAssets, vaultBalance, minAmounts);
                        assertGe(IERC20(underlying).balanceOf(address(this)), minAmounts[0], "U2");
                        assertLe(IERC20(underlying).balanceOf(address(this)), totalWas + 10);
                    } else {
                        {
                            vm.expectRevert(abi.encodeWithSelector(IControllable.NotVault.selector));
                            strategy.depositUnderlying(18);
                            vm.startPrank(strategy.vault());
                            vm.expectRevert("no underlying");
                            strategy.depositUnderlying(18);
                            vm.expectRevert("no underlying");
                            strategy.withdrawUnderlying(18, address(123));
                            vm.stopPrank();
                        }
                    }
                }

                (uint uniqueInitAddresses, uint uniqueInitNums) = IVault(vars.vault).getUniqueInitParamLength();
                assertEq(uniqueInitAddresses, 1);
                assertEq(uniqueInitNums, 0);

                /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                /*                          TEST ZAP                          */
                /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
                {
                    IZap zap = IZap(platform.zap());
                    (, uint[] memory swapAmounts) =
                        zap.getDepositSwapAmounts(vars.vault, platform.targetExchangeAsset(), 1000e6);
                    assertEq(swapAmounts.length, assets.length);
                }

                /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                /*                      TEST BASE CONTRACTS                   */
                /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
                if (vars.isLPStrategy) {
                    // check LPStrategyBase reverts
                    {
                        address[] memory wrongAssets = new address[](10);
                        vm.expectRevert(ILPStrategy.IncorrectAssetsLength.selector);
                        strategy.previewDepositAssets(wrongAssets, depositAmounts);
                        wrongAssets = new address[](assets.length);
                        wrongAssets[0] = address(1);
                        vm.expectRevert(ILPStrategy.IncorrectAssets.selector);
                        strategy.previewDepositAssets(wrongAssets, depositAmounts);
                        vm.expectRevert(ILPStrategy.IncorrectAmountsLength.selector);
                        strategy.previewDepositAssets(assets, new uint[](5));
                    }
                }

                // check ERC165
                assertEq(strategy.supportsInterface(type(IERC165).interfaceId), true);
                assertEq(strategy.supportsInterface(type(IControllable).interfaceId), true);
                assertEq(strategy.supportsInterface(type(IStrategy).interfaceId), true);

                assertEq(strategy.supportsInterface(type(IERC721).interfaceId), false);
                assertEq(strategy.supportsInterface(type(IERC721Metadata).interfaceId), false);
                assertEq(strategy.supportsInterface(type(IERC721Enumerable).interfaceId), false);

                if (keccak256(bytes(strategy.strategyLogicId())) == keccak256(bytes(strategyId))) {
                    assertEq(strategy.supportsInterface(type(ILPStrategy).interfaceId), true);
                    assertEq(strategy.supportsInterface(type(IFarmingStrategy).interfaceId), true);
                    assertEq(strategy.supportsInterface(type(IStrategy).interfaceId), true);
                }

                /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                /*                         EMERGENCY                          */
                /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

                vars.depositUsdValue = 0;
                for (uint j; j < assets.length; ++j) {
                    (uint price,) = IPriceReader(platform.priceReader()).getPrice(assets[j]);
                    depositAmounts[j] = 1000 * 10 ** IERC20Metadata(assets[j]).decimals() * 1e18 / price;
                    _deal(assets[j], address(this), depositAmounts[j]);
                    IERC20(assets[j]).approve(vars.vault, depositAmounts[j]);
                    vars.depositUsdValue += depositAmounts[j] * price / 10 ** IERC20Metadata(assets[j]).decimals();
                }
                IVault(vars.vault).depositAssets(assets, depositAmounts, 0, address(0));
                vm.roll(block.number + 6);
                (tvl,) = IVault(vars.vault).tvl();

                vm.prank(platform.multisig());
                strategy.emergencyStopInvesting();
                assertEq(strategy.total(), 0);

                IVault(vars.vault).withdrawAssets(
                    assets, IERC20(vars.vault).balanceOf(address(this)), new uint[](assets.length)
                );

                vars.withdrawnUsdValue = 0;
                for (uint j; j < assets.length; ++j) {
                    (uint price,) = IPriceReader(platform.priceReader()).getPrice(assets[j]);
                    uint balNow = IERC20(assets[j]).balanceOf(address(this));
                    vars.withdrawnUsdValue += balNow * price / 10 ** IERC20Metadata(assets[j]).decimals();
                }
                assertGe(vars.withdrawnUsdValue, vars.depositUsdValue * 93_00 / 100_00, "E1");

                /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                /*                         COVERAGE                           */
                /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
                strategy.isHardWorkOnDepositAllowed();
                if (vars.farming) {
                    IFarmingStrategy(address(strategy)).farmMechanics();
                    IFarmingStrategy(address(strategy)).stakingPool();
                }
                strategy.autoCompoundingByUnderlyingProtocol();
                if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.YEARN)) {
                    vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectMsgSender.selector));
                    IVault(vars.vault).hardWorkMintFeeCallback(new address[](0), new uint[](0));
                }

                /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                /*                       INIT VARIANTS                        */
                /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
                (string[] memory variants,,,) = strategy.initVariants(address(platform));
                assertGt(variants.length, 0, "initVariants returns empty arrays");
            }
        }
    }

    function _makePoolVolume(
        address pool,
        address ammAdapter,
        address[] memory assets_,
        uint amount0,
        uint amount1
    ) internal {
        ISwapper swapper = ISwapper(platform.swapper());
        ISwapper.PoolData[] memory poolData = new ISwapper.PoolData[](1);
        poolData[0].pool = pool;
        poolData[0].ammAdapter = ammAdapter;
        poolData[0].tokenIn = assets_[0];
        poolData[0].tokenOut = assets_[1];
        IERC20(assets_[0]).approve(address(swapper), amount0);
        // incrementing need for some tokens with custom fee
        _deal(assets_[0], address(this), amount0 + 1);
        swapper.swapWithRoute(poolData, amount0, makePoolVolumePriceImpactTolerance);

        _rebalance();

        poolData[0].tokenIn = assets_[1];
        poolData[0].tokenOut = assets_[0];
        IERC20(assets_[1]).approve(address(swapper), amount1);
        // incrementing need for some tokens with custom fee
        _deal(assets_[1], address(this), amount1 + 1);
        swapper.swapWithRoute(poolData, amount1, makePoolVolumePriceImpactTolerance);

        _rebalance();
    }

    /// @notice Deal underlying asset to an address and check result balance
    /// @dev Deal doesn't work with aave tokens, so let's make a way to provide underlying in custom way
    /// @dev https://github.com/foundry-rs/forge-std/issues/140
    function _dealUnderlying(address underlying, address to, uint amount) internal virtual {
        deal(underlying, to, amount);
        assertEq(IERC20(underlying).balanceOf(to), amount, "U1");
    }

    /// @dev Provide a virtual function to prepare extended tests of maxWithdraw
    /// Default implementation checks only lengths
    function _checkMaxWithdraw() internal virtual returns (bool) {
        IStrategy strategy = IStrategy(currentStrategy);
        uint[] memory maxWithdraw = strategy.maxWithdrawAssets(0);
        (, uint[] memory assetAmounts) = strategy.assetsAmounts();

        // maxWithdraw has same length as assetAmounts OR it's empty (there are no limits for withdraw)
        return maxWithdraw.length == assetAmounts.length || maxWithdraw.length == 0;
    }

    /// @dev Provide a virtual function to prepare extended tests of maxDeposit
    /// Default implementation checks only lengths
    function _checkMaxDeposit() internal virtual returns (bool) {
        IStrategy strategy = IStrategy(currentStrategy);
        uint[] memory maxDeposit = strategy.maxDepositAssets();
        (, uint[] memory assetAmounts) = strategy.assetsAmounts();

        // maxDeposit has same length as assetAmounts OR it's empty (there are no limits for deposit)
        return maxDeposit.length == assetAmounts.length || maxDeposit.length == 0;
    }

    /// @dev Provide a virtual function to prepare extended tests of poolTvl
    /// Default implementation checks tvl != 0 only
    function _checkPoolTvl() internal virtual returns (bool) {
        IStrategy strategy = IStrategy(currentStrategy);

        // Assume that internal pool has some TVL
        return strategy.poolTvl() != 0;
    }
}
