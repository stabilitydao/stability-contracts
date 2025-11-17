// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {EthereumLib} from "../../chains/EthereumLib.sol";
import {EthereumSetup} from "../base/chains/EthereumSetup.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {UniversalTest} from "../base/UniversalTest.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";
import {IAaveAddressProvider} from "../../src/integrations/aave/IAaveAddressProvider.sol";
import {IAavePriceOracle} from "../../src/integrations/aave/IAavePriceOracle.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";
import {console} from "forge-std/console.sol";

contract ALMFStrategyEthereumTest is EthereumSetup, UniversalTest {
    uint public constant REVERT_NO = 0;
    uint public constant REVERT_NOT_ENOUGH_LIQUIDITY = 1;
    uint public constant REVERT_INSUFFICIENT_BALANCE = 2;

    uint internal constant INDEX_INIT_0 = 0;
    uint internal constant INDEX_AFTER_DEPOSIT_1 = 1;
    uint internal constant INDEX_AFTER_WAIT_2 = 2;
    uint internal constant INDEX_AFTER_HARDWORK_3 = 3;
    uint internal constant INDEX_AFTER_WITHDRAW_4 = 4;

    struct State {
        uint ltv;
        uint maxLtv;
        uint leverage;
        uint maxLeverage;
        uint targetLeverage;
        uint targetLeveragePercent;
        uint collateralAmount;
        uint debtAmount;
        uint total;
        uint sharePrice;
        uint strategyBalanceAsset;
        uint userBalanceAsset;
        uint realTvl;
        uint realSharePrice;
        uint vaultBalance;
        address[] revenueAssets;
        uint[] revenueAmounts;
    }

    uint internal constant FORK_BLOCK = 23819383; // Nov-17-2025 02:07:23 PM +UTC

    address internal constant POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal constant ATOKEN_USDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address internal constant ATOKEN_WBTC = 0x5Ee5bf7ae06D1Be5997A1A72006FE6C607eC6DE8;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("ETHEREUM_RPC_URL"), FORK_BLOCK));

        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;

        // ALMF uses real share price as share price
        // so it cannot initialize share price during deposit.
        // It sets initial value of share price in first claimRevenue.
        // As result, following check is failed in universal test:
        // "Universal test: estimated totalRevenueUSD is zero"
        // So, we should disable it by setting allowZeroTotalRevenueUSD.
        // And make all checks in additional tests instead.
        allowZeroTotalRevenueUSD = true;

        // _upgradePlatform(platform.multisig(), IPlatform(PLATFORM).priceReader());
    }

    //region --------------------------------------- Universal test
    function testALMFEthereum() public universalTest {
        _addStrategy(_addFarm());
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.AAVE_LEVERAGE_MERKL_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }

    function _addFarm() internal returns (uint farmId) {
        address[] memory rewards = new address[](1);
        rewards[0] = EthereumLib.TOKEN_USDC;
        // todo rewards[1] = EthereumLib.TOKEN_WXPL;

        IFactory.Farm[] memory farms = new IFactory.Farm[](1);
        farms[0] = EthereumLib._makeAaveLeverageMerklFarm(
            ATOKEN_WBTC,
            ATOKEN_USDC,
            EthereumLib.POOL_UNISWAPV3_USDC_WETH_500,
            rewards,
            49_00, // min target ltv
            50_97, // max target ltv
            uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2)
        );

        vm.startPrank(platform.multisig());
        factory.addFarms(farms);

        return factory.farmsLength() - 1;
    }

    function _preDeposit() internal override {
        // ---------------------------------- Make additional tests
        uint snapshot = vm.snapshotState();

        // initial supply
        _tryToDepositToVault(IStrategy(currentStrategy).vault(), 0.1e18, REVERT_NO, makeAddr("initial supplier"));

        // check revenue (replacement for "Universal test: estimated totalRevenueUSD is zero")
        _testDepositTwoHardworks();

        // set TL, deposit, change TL, withdraw/deposit => leverage was changed toward new TL
        _testDepositChangeLtvWithdraw();
        _testDepositChangeLtvDeposit();

        // check deposit-wait 30 days-hardwork-withdraw results
        _testDepositWaitHardworkWithdraw();

        vm.revertToState(snapshot);
    }

    function _preHardWork() internal override {
        // emulate merkl rewards
        deal(EthereumLib.TOKEN_USDC, currentStrategy, 1e6);
        deal(EthereumLib.TOKEN_WETH, currentStrategy, 1e18);
    }

    //endregion --------------------------------------- Universal test

    //region --------------------------------------- Additional tests
    function _testDepositTwoHardworks() internal {
        uint amount = 1e18;

        uint priceWeth8 = _getWethPrice8();

        IStrategy strategy = IStrategy(currentStrategy);

        // --------------------------------------------- Deposit
        State memory stateAfterDeposit = _getState();
        _tryToDepositToVault(strategy.vault(), amount, REVERT_NO, address(this));
        vm.roll(block.number + 6);

        // --------------------------------------------- Hardwork 1
        _skip(1 days, 0);
        deal(EthereumLib.TOKEN_USDC, currentStrategy, 100e6);

        vm.prank(platform.multisig());
        IVault(strategy.vault()).doHardWork();

        State memory stateAfterHW1 = _getState();

        // --------------------------------------------- Hardwork 2
        _skip(1 days, 0);
        deal(EthereumLib.TOKEN_USDC, currentStrategy, 300e6);

        vm.prank(platform.multisig());
        IVault(strategy.vault()).doHardWork();

        State memory stateAfterHW2 = _getState();

        assertEq(
            stateAfterDeposit.revenueAmounts[0],
            0,
            "Revenue before first claimReview is 0 because share price is not initialized yet"
        );
        assertApproxEqRel(
            stateAfterHW1.revenueAmounts[0] * priceWeth8 * 1e6 / 1e8 / 1e18,
            100e6,
            2e16,
            "Revenue after first hardwork is ~$100"
        );
        assertApproxEqRel(
            stateAfterHW2.revenueAmounts[0] * priceWeth8 * 1e6 / 1e8 / 1e18,
            300e6,
            2e16,
            "Revenue after first hardwork is ~$300"
        );
    }

    function _testDepositChangeLtvWithdraw() internal {
        {
            (, State memory stateAfterDeposit, State memory stateAfterWithdraw) =
                _depositChangeLtvWithdraw(49_00, 50_97, 52_00, 51_97);

            assertApproxEqRel(
                stateAfterDeposit.leverage,
                stateAfterDeposit.targetLeverage,
                1e16,
                "Leverage after deposit should be equal to target 111"
            );
            assertLt(
                stateAfterDeposit.leverage,
                stateAfterWithdraw.targetLeverage,
                "leverage before withdraw less than target"
            );
            assertGt(stateAfterWithdraw.leverage, stateAfterDeposit.leverage, "withdraw increased the leverage");
        }
        {
            (, State memory stateAfterDeposit, State memory stateAfterWithdraw) =
                _depositChangeLtvWithdraw(49_00, 50_97, 47_00, 48_97);

            assertApproxEqRel(
                stateAfterDeposit.leverage,
                stateAfterDeposit.targetLeverage,
                1e16,
                "Leverage after deposit should be equal to target 222"
            );
            assertGt(
                stateAfterDeposit.leverage,
                stateAfterWithdraw.targetLeverage,
                "leverage before withdraw greater than target"
            );
            assertLt(stateAfterWithdraw.leverage, stateAfterDeposit.leverage, "withdraw decreased the leverage");
        }
    }

    function _testDepositChangeLtvDeposit() internal {
        {
            (, State memory stateAfterDeposit, State memory stateAfterDeposit2) =
                _depositChangeLtvDeposit(49_00, 50_97, 52_00, 51_97);

            assertApproxEqRel(
                stateAfterDeposit.leverage,
                stateAfterDeposit.targetLeverage,
                1e16,
                "Leverage after deposit should be equal to target 333"
            );
            assertLt(
                stateAfterDeposit.leverage,
                stateAfterDeposit2.targetLeverage,
                "leverage before withdraw less than target"
            );
            assertGt(stateAfterDeposit2.leverage, stateAfterDeposit.leverage, "deposit2 increased the leverage");
        }
        {
            (, State memory stateAfterDeposit, State memory stateAfterDeposit2) =
                _depositChangeLtvDeposit(49_00, 50_97, 47_00, 48_97);

            assertApproxEqRel(
                stateAfterDeposit.leverage,
                stateAfterDeposit.targetLeverage,
                1e16,
                "Leverage after deposit should be equal to target 444"
            );
            assertGt(
                stateAfterDeposit.leverage,
                stateAfterDeposit2.targetLeverage,
                "leverage before deposit2 greater than target"
            );
            assertLt(stateAfterDeposit2.leverage, stateAfterDeposit.leverage, "deposit2 decreased the leverage");
        }
    }

    function _testDepositWithdrawUsingFlashLoan(
        address flashLoanVault,
        ILeverageLendingStrategy.FlashLoanKind kind_
    ) internal {
        uint snapshot = vm.snapshotState();
        _setUpFlashLoanVault(flashLoanVault, kind_);

        uint amount = 1e18;
        State[] memory states = _depositWithdraw(amount, EthereumLib.TOKEN_USDC, 0, 0, false);
        vm.revertToState(snapshot);

        assertApproxEqRel(
            states[INDEX_AFTER_WITHDRAW_4].total,
            states[INDEX_INIT_0].total,
            states[INDEX_INIT_0].total / 100_000,
            "Total should return back to prev value"
        );
        assertApproxEqRel(states[4].userBalanceAsset, amount, amount / 50, "User shouldn't loss more than 2%");
    }

    function _testDepositWaitHardworkWithdraw() internal {
        uint amount = 1e18;

        // --------------------------------------------- Deposit+withdraw without hardwork
        uint snapshot = vm.snapshotState();
        State[] memory statesInstant = _depositWithdraw(amount, EthereumLib.TOKEN_USDC, 0, 0, true);
        vm.revertToState(snapshot);

        // --------------------------------------------- Deposit, wait, [no rewards], hardwork, withdraw
        snapshot = vm.snapshotState();
        State[] memory statesHW1 = _depositWithdraw(amount, EthereumLib.TOKEN_USDC, 0, 1 days, true);
        vm.revertToState(snapshot);

        // --------------------------------------------- Deposit, wait, rewards, hardwork, withdraw
        snapshot = vm.snapshotState();
        State[] memory statesHW2 = _depositWithdraw(amount, EthereumLib.TOKEN_USDC, 100e6, 1 days, true);
        vm.revertToState(snapshot);

        // --------------------------------------------- Get WETH price
        uint wethPrice = _getWethPrice8();

        // --------------------------------------------- Compare results
        assertApproxEqAbs(
            statesHW2[INDEX_AFTER_HARDWORK_3].total - statesInstant[INDEX_AFTER_HARDWORK_3].total,
            100e18,
            3e18,
            "total is increased on rewards amount - fees"
        );
        assertLt(
            statesHW1[INDEX_AFTER_HARDWORK_3].total,
            statesInstant[INDEX_AFTER_HARDWORK_3].total,
            "total is decreased because the borrow rate exceeds supply rate"
        );

        assertLt(
            statesHW1[INDEX_AFTER_WITHDRAW_4].userBalanceAsset,
            statesInstant[INDEX_AFTER_WITHDRAW_4].userBalanceAsset,
            "user lost some amount because of borrow rate"
        );
        assertApproxEqRel(
            statesHW2[INDEX_AFTER_WITHDRAW_4].userBalanceAsset,
            100e18 * wethPrice / 1e18 + statesInstant[INDEX_AFTER_WITHDRAW_4].userBalanceAsset,
            3e16, //  < 3%
            "user received almost all rewards"
        );
    }

    function _testMaxDepositAndMaxWithdraw() internal view {
        assertEq(IStrategy(currentStrategy).maxDepositAssets().length, 0, "any amount can be deposited");
        assertEq(IStrategy(currentStrategy).maxWithdrawAssets(0).length, 0, "any amount can be withdrawn");
    }

    //endregion --------------------------------------- Additional tests

    //region --------------------------------------- Test implementations
    function _depositChangeLtvWithdraw(
        uint minLtv0,
        uint maxLtv0,
        uint minLtv1,
        uint maxLtv1
    ) internal returns (State memory stateInitial, State memory stateAfterDeposit, State memory stateAfterWithdraw) {
        uint snapshot = vm.snapshotState();
        address vault = IStrategy(currentStrategy).vault();
        _setMinMaxLtv(minLtv0, maxLtv0);

        stateInitial = _getState();

        _tryToDepositToVault(vault, 1e18, 0, address(this));
        stateAfterDeposit = _getState();

        vm.roll(block.number + 6);

        _setMinMaxLtv(minLtv1, maxLtv1);

        _tryToWithdrawFromVault(vault, IVault(vault).balanceOf(address(this)));
        stateAfterWithdraw = _getState();

        vm.revertToState(snapshot);
    }

    function _depositChangeLtvDeposit(
        uint minLtv0,
        uint maxLtv0,
        uint minLtv1,
        uint maxLtv1
    ) internal returns (State memory stateInitial, State memory stateAfterDeposit, State memory stateAfterDeposit2) {
        uint snapshot = vm.snapshotState();
        address vault = IStrategy(currentStrategy).vault();
        _setMinMaxLtv(minLtv0, maxLtv0);

        stateInitial = _getState();

        _tryToDepositToVault(vault, 1e18, 0, address(this));
        stateAfterDeposit = _getState();

        vm.roll(block.number + 6);

        _setMinMaxLtv(minLtv1, maxLtv1);

        _tryToDepositToVault(vault, 1e18, 0, address(this));
        stateAfterDeposit2 = _getState();

        vm.revertToState(snapshot);
    }

    /// @notice Deposit, check state, withdraw all, check state
    /// @return states [initial state, state after deposit, state after waiting, state after hardwork, state after withdraw]
    function _depositWithdraw(
        uint amount,
        address rewards,
        uint rewardsAmount,
        uint waitSec,
        bool hardworkBeforeWithdraw
    ) internal returns (State[] memory states) {
        uint snapshot = vm.snapshotState();
        states = new State[](5);

        IStrategy strategy = IStrategy(currentStrategy);

        // --------------------------------------------- Deposit
        states[0] = _getState();
        (uint depositedAssets,) = _tryToDepositToVault(strategy.vault(), amount, REVERT_NO, address(this));
        vm.roll(block.number + 6);
        states[1] = _getState();

        _skip(waitSec, 0);
        states[2] = _getState();

        // --------------------------------------------- Hardwork
        if (rewardsAmount != 0) {
            // emulate merkl rewards
            deal(rewards, currentStrategy, rewardsAmount);
        }

        if (hardworkBeforeWithdraw) {
            vm.prank(platform.multisig());
            IVault(strategy.vault()).doHardWork();
        }
        states[3] = _getState();

        // --------------------------------------------- Withdraw
        _tryToWithdrawFromVault(strategy.vault(), states[1].vaultBalance - states[0].vaultBalance);
        vm.roll(block.number + 6);
        states[4] = _getState();

        vm.revertToState(snapshot);

        assertLt(states[0].total, states[1].total, "Total should increase after deposit");
        assertEq(depositedAssets, amount, "Deposited amount should be equal to amountsToDeposit");
    }

    //endregion --------------------------------------- Test implementations

    //region --------------------------------------- Internal logic
    function _currentFarmId() internal view returns (uint) {
        return IFarmingStrategy(currentStrategy).farmId();
    }

    function _tryToDepositToVault(
        address vault,
        uint amount,
        uint revertKind,
        address user
    ) internal returns (uint deposited, uint depositedValue) {
        address[] memory assets = IVault(vault).assets();
        uint[] memory amountsToDeposit = new uint[](1);
        amountsToDeposit[0] = amount;

        // ----------------------------- Prepare amount on user's balance
        _dealAndApprove(user, vault, assets, amountsToDeposit);
        // console.log("Deposit to vault", assets[0], amounts_[0]);

        uint balanceBefore = IVault(vault).balanceOf(user);
        // ----------------------------- Try to deposit assets to the vault
        // todo
        //        if (revertKind == REVERT_NOT_ENOUGH_LIQUIDITY) {
        //            vm.expectRevert(ISilo.NotEnoughLiquidity.selector);
        //        }
        if (revertKind == REVERT_INSUFFICIENT_BALANCE) {
            vm.expectRevert(IControllable.InsufficientBalance.selector);
        }
        vm.prank(user);
        IStabilityVault(vault).depositAssets(assets, amountsToDeposit, 0, user);

        return (amountsToDeposit[0], IVault(vault).balanceOf(user) - balanceBefore);
    }

    function _tryToWithdrawFromVault(address vault, uint values) internal returns (uint withdrawn) {
        address[] memory _assets = IVault(vault).assets();

        uint balanceBefore = IERC20(_assets[0]).balanceOf(address(this));

        vm.prank(address(this));
        IStabilityVault(vault).withdrawAssets(_assets, values, new uint[](1));

        return IERC20(_assets[0]).balanceOf(address(this)) - balanceBefore;
    }

    function _dealAndApprove(address user, address spender, address[] memory assets, uint[] memory amounts) internal {
        for (uint j; j < assets.length; ++j) {
            deal(assets[j], user, amounts[j]);

            vm.prank(user);
            IERC20(assets[j]).approve(spender, amounts[j]);
        }
    }

    /// @param depositParam0 - Multiplier of flash amount for borrow on deposit.
    /// @param depositParam1 - Multiplier of borrow amount to take into account max flash loan fee in maxDeposit
    function _setDepositParams(uint depositParam0, uint depositParam1) internal {
        ILeverageLendingStrategy strategy = ILeverageLendingStrategy(currentStrategy);
        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();

        params[0] = depositParam0;
        params[1] = depositParam1;

        vm.prank(platform.multisig());
        strategy.setUniversalParams(params, addresses);
    }

    /// @param withdrawParam0 - Multiplier of flash amount for borrow on withdraw.
    /// @param withdrawParam1 - Multiplier of amount allowed to be deposited after withdraw. Default is 100_00 == 100% (deposit forbidden)
    /// @param withdrawParam2 - allows to disable withdraw through increasing ltv if leverage is near to target
    function _setWithdrawParams(uint withdrawParam0, uint withdrawParam1, uint withdrawParam2) internal {
        ILeverageLendingStrategy strategy = ILeverageLendingStrategy(currentStrategy);
        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();

        params[2] = withdrawParam0;
        params[3] = withdrawParam1;
        params[11] = withdrawParam2;

        vm.prank(platform.multisig());
        strategy.setUniversalParams(params, addresses);
    }

    function _getState() internal view returns (State memory state) {
        ILeverageLendingStrategy strategy = ILeverageLendingStrategy(address(currentStrategy));

        (state.sharePrice,) = strategy.realSharePrice();

        (
            state.ltv,
            state.maxLtv,
            state.leverage,
            state.collateralAmount,
            state.debtAmount,
            state.targetLeveragePercent
        ) = strategy.health();

        state.total = IStrategy(currentStrategy).total();
        state.maxLeverage = 100_00 * 1e4 / (1e4 - state.maxLtv);
        state.targetLeverage = state.maxLeverage * state.targetLeveragePercent / 100_00;
        state.strategyBalanceAsset =
            IERC20(IStrategy(address(strategy)).assets()[0]).balanceOf(address(currentStrategy));
        state.userBalanceAsset = IERC20(IStrategy(address(strategy)).assets()[0]).balanceOf(address(address(this)));
        (state.realTvl,) = strategy.realTvl();
        (state.realSharePrice,) = strategy.realSharePrice();
        state.vaultBalance = IVault(IStrategy(address(strategy)).vault()).balanceOf(address(this));
        (state.revenueAssets, state.revenueAmounts) = IStrategy(currentStrategy).getRevenue();

        // _printState(state);
        return state;
    }

    function _printState(State memory state) internal pure {
        console.log("state **************************************************");
        console.log("ltv", state.ltv);
        console.log("maxLtv", state.maxLtv);
        console.log("targetLeverage", state.targetLeverage);
        console.log("leverage", state.leverage);
        console.log("total", state.total);
        console.log("collateralAmount", state.collateralAmount);
        console.log("debtAmount", state.debtAmount);
        console.log("targetLeveragePercent", state.targetLeveragePercent);
        console.log("maxLeverage", state.maxLeverage);
        console.log("realTvl", state.realTvl);
        console.log("realSharePrice", state.realSharePrice);
        console.log("vaultBalance", state.vaultBalance);
        console.log("strategyBalanceAsset", state.strategyBalanceAsset);
        console.log("userBalanceAsset", state.userBalanceAsset);
        for (uint i = 0; i < state.revenueAssets.length; i++) {
            console.log("revenueAsset", i, state.revenueAssets[i], state.revenueAmounts[i]);
        }
    }

    function _setMinMaxLtv(uint minLtv, uint maxLtv) internal {
        IFarmingStrategy strategy = IFarmingStrategy(currentStrategy);
        uint farmId = strategy.farmId();
        IFactory factory = IFactory(IPlatform(IControllable(currentStrategy).platform()).factory());

        IFactory.Farm memory farm = factory.farm(farmId);
        farm.nums[0] = minLtv;
        farm.nums[1] = maxLtv;

        vm.prank(platform.multisig());
        factory.updateFarm(farmId, farm);
    }

    //endregion --------------------------------------- Internal logic

    //region --------------------------------------- Helper functions
    function _upgradePlatform(address multisig, address priceReader_) internal {
        // we need to skip 1 day to update the swapper
        // but we cannot simply skip 1 day, because the silo oracle will start to revert with InvalidPrice
        // vm.warp(block.timestamp - 86400);
        rewind(86400);

        IPlatform platform = IPlatform(IControllable(priceReader_).platform());

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = address(priceReader_);
        //proxies[1] = platform.swapper();
        //proxies[2] = platform.ammAdapter(keccak256(bytes(AmmAdapterIdLib.META_VAULT))).proxy;

        implementations[0] = address(new PriceReader());
        //implementations[1] = address(new Swapper());
        //implementations[2] = address(new MetaVaultAdapter());

        //vm.prank(multisig);
        // platform.cancelUpgrade();

        vm.startPrank(multisig);
        platform.announcePlatformUpgrade("2025.07.22-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }

    function _setUpFlashLoanVault(address flashLoanVault, ILeverageLendingStrategy.FlashLoanKind kind_) internal {
        _setFlashLoanVault(ILeverageLendingStrategy(currentStrategy), flashLoanVault, uint(kind_));
    }

    function _setFlashLoanVault(ILeverageLendingStrategy strategy, address flashLoanVault, uint kind) internal {
        address multisig = platform.multisig();

        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
        params[10] = kind;
        addresses[0] = flashLoanVault;

        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
    }

    function _getWethPrice8() internal view returns (uint) {
        return IAavePriceOracle(IAaveAddressProvider(IPool(POOL).ADDRESSES_PROVIDER()).getPriceOracle())
            .getAssetPrice(EthereumLib.TOKEN_WETH);
    }

    //endregion --------------------------------------- Helper functions
}
