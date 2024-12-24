// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./ChainSetup.sol";
import "./Utils.sol";
import "../../src/core/libs/VaultTypeLib.sol";
import "../../src/strategies/base/StrategyBase.sol";
import "../../src/strategies/base/FarmingStrategyBase.sol";
import "../../src/strategies/libs/UniswapV3MathLib.sol";
import "../../src/strategies/libs/StrategyDeveloperLib.sol";
import "../../src/interfaces/ISwapper.sol";
import "../../src/interfaces/IFactory.sol";
import "../../src/interfaces/IStrategy.sol";
import "../../src/interfaces/ILPStrategy.sol";
import "../../src/interfaces/IStrategyLogic.sol";
import "../../src/interfaces/IVault.sol";
import "../../src/interfaces/IRVault.sol";
import "../../src/interfaces/IPriceReader.sol";
import "../../src/interfaces/IFarmingStrategy.sol";
import "../../src/interfaces/ILPStrategy.sol";
import "../../src/interfaces/IHardWorker.sol";
import "../../src/interfaces/IZap.sol";

abstract contract UniversalTest is Test, ChainSetup, Utils {
    Strategy[] public strategies;
    string public strategyId;
    address internal currentStrategy;
    uint[] public specialDepositAmounts;
    uint public duration1 = 6 hours;
    uint public duration2 = 3 hours;
    uint public duration3 = 3 hours;
    uint public buildingPayPerVaultTokenAmount = 5e24;

    struct Strategy {
        string id;
        address pool;
        uint farmId;
        address underlying;
    }

    struct TestStrategiesVars {
        bool isLPStrategy;
        address[] allowedBBTokens;
        address strategyLogic;
        address strategyImplementation;
        bool farming;
        uint tokenId;
        string[] types;
        IHardWorker hardWorker;
        address vault;
        address[] vaultsForHardWork;
        bool isRVault;
        bool isRMVault;
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
    }

    modifier universalTest() {
        _init();
        _;
        _testStrategies();
    }

    function _addRewards(uint farmId) internal virtual {}

    function _preHardWork() internal virtual {}

    function _preHardWork(uint farmId) internal virtual {}

    function _preDeposit() internal virtual {}

    function _skip(uint time, uint) internal virtual {
        skip(time);
    }

    function testNull() public {}

    function _testStrategies() internal {
        console.log(string.concat("Universal test of strategy logic", strategyId));
        _deal(platform.buildingPayPerVaultToken(), address(this), buildingPayPerVaultTokenAmount);
        IERC20(platform.buildingPayPerVaultToken()).approve(address(factory), buildingPayPerVaultTokenAmount);
        TestStrategiesVars memory vars;
        vars.hardWorker = IHardWorker(platform.hardWorker());
        vm.startPrank(platform.governance());
        vars.hardWorker.setDedicatedServerMsgSender(address(this), true);
        vm.expectRevert(abi.encodeWithSelector(IControllable.AlreadyExist.selector));
        vars.hardWorker.setDedicatedServerMsgSender(address(this), true);
        vm.stopPrank();
        vars.vaultsForHardWork = new address[](1);
        vars.allowedBBTokens = platform.allowedBBTokens();
        if (vars.allowedBBTokens.length > 0) {
            platform.setAllowedBBTokenVaults(vars.allowedBBTokens[0], 1e6);
        }
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

                vars.isRVault = CommonLib.eq(vars.types[k], VaultTypeLib.REWARDING);
                vars.isRMVault = CommonLib.eq(vars.types[k], VaultTypeLib.REWARDING_MANAGED);
                {
                    address[] memory vaultInitAddresses = new address[](0);
                    uint[] memory vaultInitNums = new uint[](0);
                    if (vars.isRVault) {
                        vaultInitAddresses = new address[](1);
                        vaultInitAddresses[0] = vars.allowedBBTokens[0];
                        vaultInitNums =
                            new uint[](1 + platform.defaultBoostRewardTokensFiltered(vars.allowedBBTokens[0]).length);
                        vaultInitNums[0] = 3000e18; // 3k PROFIT
                        deal(vaultInitAddresses[0], address(this), 3000e18);
                        IERC20(vaultInitAddresses[0]).approve(address(factory), 3000e18);
                    }
                    if (vars.isRMVault) {
                        vaultInitAddresses = new address[](2);
                        uint vaultInitAddressesLength = vaultInitAddresses.length;
                        // bbToken
                        vaultInitAddresses[0] = vars.allowedBBTokens[0];
                        // boost reward tokens
                        vaultInitAddresses[1] = platform.targetExchangeAsset();
                        vaultInitNums = new uint[](vaultInitAddressesLength * 2);
                        // bbToken vesting duration
                        vaultInitNums[0] = 3600;
                        for (uint e = 1; e < vaultInitAddressesLength; ++e) {
                            vaultInitNums[e] = 86400 * 30;
                            vaultInitNums[e + vaultInitAddressesLength - 1] = 1000e6; // 1000 usdc
                            deal(vaultInitAddresses[e], address(this), 1000e6);
                            IERC20(vaultInitAddresses[e]).approve(address(factory), 1000e6);
                        }
                        // compoundRatuo
                        vaultInitNums[vaultInitAddressesLength * 2 - 1] = 50_000;
                    }

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
                        initStrategyAddresses = new address[](2);
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

                        initStrategyAddresses = new address[](1);
                        initStrategyAddresses[0] = strategies[i].underlying;
                        nums = new uint[](0);
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

                console.log(
                    string.concat(
                        IERC20Metadata(vars.vault).symbol(),
                        " [Compound ratio: ",
                        vars.isRVault || vars.isRMVault
                            ? CommonLib.u2s(IRVault(vars.vault).compoundRatio() / 1000)
                            : "100",
                        "%]. Name: ",
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

                    require(price > 0, "UniversalTest: price is zero. Forget to add swapper routes?");
                    depositAmounts[j] = 1000 * 10 ** IERC20Metadata(assets[j]).decimals() * 1e18 / price;
                    _deal(assets[j], address(this), depositAmounts[j]);
                    IERC20(assets[j]).approve(vars.vault, depositAmounts[j]);
                }

                // deposit
                IVault(vars.vault).depositAssets(assets, depositAmounts, 0, address(0));
                (tvl,) = IVault(vars.vault).tvl();
                assertGt(tvl, 0, "Universal test: tvl is zero");

                _skip(duration1, strategies[i].farmId);

                if (vars.isLPStrategy) {
                    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                    /*                       MAKE POOL VOLUME                     */
                    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
                    {
                        ISwapper swapper = ISwapper(platform.swapper());
                        ISwapper.PoolData[] memory poolData = new ISwapper.PoolData[](1);
                        poolData[0].pool = vars.pool;
                        poolData[0].ammAdapter = vars.ammAdapter;
                        poolData[0].tokenIn = assets[0];
                        poolData[0].tokenOut = assets[1];
                        IERC20(assets[0]).approve(address(swapper), depositAmounts[0]);
                        // incrementing need for some tokens with custom fee
                        _deal(assets[0], address(this), depositAmounts[0] + 1);
                        swapper.swapWithRoute(poolData, depositAmounts[0], 6_000);

                        poolData[0].tokenIn = assets[1];
                        poolData[0].tokenOut = assets[0];
                        IERC20(assets[1]).approve(address(swapper), depositAmounts[1]);
                        // incrementing need for some tokens with custom fee
                        _deal(assets[1], address(this), depositAmounts[1] + 1);
                        swapper.swapWithRoute(poolData, depositAmounts[1], 6_000);
                    }
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

                if (vars.isLPStrategy) {
                    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
                    /*                       MAKE POOL VOLUME                     */
                    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
                    {
                        ISwapper swapper = ISwapper(platform.swapper());
                        ISwapper.PoolData[] memory poolData = new ISwapper.PoolData[](1);
                        poolData[0].pool = vars.pool;
                        poolData[0].ammAdapter = vars.ammAdapter;
                        poolData[0].tokenIn = assets[0];
                        poolData[0].tokenOut = assets[1];
                        IERC20(assets[0]).approve(address(swapper), depositAmounts[0] * 2);
                        _deal(assets[0], address(this), depositAmounts[0] * 2);
                        swapper.swapWithRoute(poolData, depositAmounts[0] * 2, 6_000);

                        poolData[0].tokenIn = assets[1];
                        poolData[0].tokenOut = assets[0];
                        IERC20(assets[1]).approve(address(swapper), depositAmounts[1] * 2);
                        _deal(assets[1], address(this), depositAmounts[1] * 2);
                        swapper.swapWithRoute(poolData, depositAmounts[1] * 2, 6_000);
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

                            assertGt(tempApr, 0, "HardWork APR");
                            assertGt(tempEarned, 0, "HardWork Earned");
                            assertGt(tempTvl, 0, "HardWork TVL");
                            assertGt(tempDuration, 0, "HardWork duration");
                            if (!vars.isRVault && !vars.isRMVault) {
                                assertGt(tempAprCompound, 0, "Hardwork APR compound is zero. Check _compound() method.");
                            }
                        }
                    }
                    require(vars.hwEventFound, "UniversalTest: HardWork event not emited");
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
                /*           CLAIM REWARDS FROM REWARDING VAULTS              */
                /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
                if (vars.isRVault || vars.isRMVault) {
                    address rewardToken = vars.isRVault ? vars.allowedBBTokens[0] : platform.targetExchangeAsset();
                    uint balanceBefore = IERC20(rewardToken).balanceOf(address(this));
                    IRVault(vars.vault).getAllRewards();
                    assertGt(IERC20(rewardToken).balanceOf(address(this)), balanceBefore, "Rewards was not claimed");
                    _skip(3600, strategies[i].farmId);
                    balanceBefore = IERC20(rewardToken).balanceOf(address(this));
                    IRVault(vars.vault).getAllRewards();
                    assertGt(
                        IERC20(rewardToken).balanceOf(address(this)),
                        balanceBefore,
                        "Rewards was not claimed after skip time"
                    );
                    balanceBefore = IERC20(rewardToken).balanceOf(address(this));
                    IRVault(vars.vault).getReward(0);
                    assertEq(IERC20(rewardToken).balanceOf(address(this)), balanceBefore);
                }

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
                        deal(underlying, address(100), underlyingAmounts[0]);
                        vm.startPrank(address(100));
                        IERC20(underlying).approve(tempVault, underlyingAmounts[0]);
                        IVault(tempVault).depositAssets(underlyingAssets, underlyingAmounts, 0, address(100));
                        vm.stopPrank();

                        _skip(7200, strategies[i].farmId);

                        bool wasReadyForHardWork = strategy.isReadyForHardWork();

                        deal(underlying, address(this), totalWas);
                        assertEq(IERC20(underlying).balanceOf(address(this)), totalWas, "U1");
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
                                sharesOut + sharesOut / 10000,
                                "previewDepositAssets by underlying: vault balance too big"
                            );
                            assertGt(
                                vaultBalance,
                                sharesOut - sharesOut / 1000,
                                "previewDepositAssets by underlying: vault balance too small"
                            );
                        }

                        uint[] memory minAmounts = new uint[](1);
                        minAmounts[0] = totalWas - 1;
                        vm.expectRevert(abi.encodeWithSelector(IVault.WaitAFewBlocks.selector));
                        IVault(tempVault).withdrawAssets(underlyingAssets, vaultBalance, minAmounts);
                        vm.roll(block.number + 6);
                        IVault(tempVault).withdrawAssets(underlyingAssets, vaultBalance, minAmounts);
                        assertGe(IERC20(underlying).balanceOf(address(this)), totalWas - 1, "U2");
                        assertLe(IERC20(underlying).balanceOf(address(this)), totalWas + 1);
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
                assertGe(vars.withdrawnUsdValue, vars.depositUsdValue - vars.depositUsdValue / 100, "E1");

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
}
