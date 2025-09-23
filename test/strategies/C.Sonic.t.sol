// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IVToken} from "../../src/integrations/compoundv2/IVToken.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {console} from "forge-std/Test.sol";

contract CompoundV2StrategyTestSonic is SonicSetup, UniversalTest {
    uint public constant FORK_BLOCK = 40868489; // Jul-30-2025 11:16:51 AM +UTC

    struct State {
        uint strategyTotal;
        uint assetUserBalance;
        uint assetStrategyBalance;
        uint userVaultBalance;
        uint assetVaultBalance;
        uint underlyingUserBalance;
        uint underlyingStrategyBalance;
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(FORK_BLOCK);
        allowZeroApr = true;
        duration1 = 10 hours;
        duration2 = 10 hours;
        duration3 = 10 hours;
        console.log("erc7201:stability.CompoundV2Strategy");
        console.logBytes32(
            keccak256(abi.encode(uint(keccak256("erc7201:stability.CompoundV2Strategy")) - 1)) & ~bytes32(uint(0xff))
        );
    }

    /// @notice Compare APR with https://stability.market/
    function testStrategies() public universalTest {
        _addStrategy(SonicConstantsLib.ENCLABS_VTOKEN_CORE_USDC);
        _addStrategy(SonicConstantsLib.ENCLABS_VTOKEN_CORE_WS);
        _addStrategy(SonicConstantsLib.ENCLABS_VTOKEN_CORE_SCUSD);
        _addStrategy(SonicConstantsLib.ENCLABS_VTOKEN_CORE_STS);

        // _addStrategy(SonicConstantsLib.ENCLABS_VTOKEN_WMETAUSD);
    }

    //region --------------------------------- Internal functions
    function _preDeposit() internal override {
        // additional tests

        // deposit - withdraw
        _testDepositWithdraw(1000);

        // deposit - withdraw underlying
        _testDepositWithdrawUnderlying(1000);

        _testMaxDeposit();
        //        if (IStrategy(currentStrategy).underlying() == SonicConstantsLib.ENCLABS_VTOKEN_CORE_USDC) {
        //            _testDepositWithdrawHardwork(5);
        //            _directDeposit();
        //        }
    }

    function _addStrategy(address aToken) internal {
        address[] memory initStrategyAddresses = new address[](1);
        initStrategyAddresses[0] = aToken;
        strategies.push(
            Strategy({
                id: StrategyIdLib.COMPOUND_V2,
                pool: address(0),
                farmId: type(uint).max,
                strategyInitAddresses: initStrategyAddresses,
                strategyInitNums: new uint[](0)
            })
        );
    }

    function _directDeposit() internal {
        uint snapshot = vm.snapshotState();
        uint usdcBalanceBefore = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this));

        IVToken token = IVToken(SonicConstantsLib.ENCLABS_VTOKEN_CORE_USDC);
        deal(SonicConstantsLib.TOKEN_USDC, address(this), 5e6);
        IERC20(SonicConstantsLib.TOKEN_USDC).approve(SonicConstantsLib.ENCLABS_VTOKEN_CORE_USDC, 5e6);

        uint vTokensBalanceBefore = token.balanceOf(address(this));
        token.mint(5e6);

        console.log("direct.rate1", token.exchangeRateStored());
        vm.warp(block.timestamp + 12209);
        vm.roll(block.number + 17497);
        //IVToken(SonicConstantsLib.ENCLABS_VTOKEN_CORE_USDC).accrueInterest();

        uint vTokensBalanceAfter = token.balanceOf(address(this));
        token.redeem(vTokensBalanceAfter - vTokensBalanceBefore);
        console.log("vTokensBalance after, before", vTokensBalanceAfter, vTokensBalanceBefore);
        console.log("direct.rate2", token.exchangeRateStored());

        uint usdcBalanceAfter = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this));
        console.log("delta usdc", usdcBalanceAfter - usdcBalanceBefore);
        vm.revertToState(snapshot);
    }

    function _testDepositWithdrawHardwork(uint amountNoDecimals) internal {
        uint snapshot = vm.snapshotState();

        IStrategy strategy = IStrategy(currentStrategy);
        address vault = strategy.vault();

        // --------------------------------------------- Initial deposit (dead shares)
        uint[] memory amountsToDeposit = new uint[](1);
        amountsToDeposit[0] = 100 * 10 ** IERC20Metadata(strategy.assets()[0]).decimals();
        _tryToDepositToVault(vault, amountsToDeposit, address(1), true);

        // --------------------------------------------- Deposit
        amountsToDeposit[0] = amountNoDecimals * 10 ** IERC20Metadata(strategy.assets()[0]).decimals();

        // State memory state0 = _getState();
        _tryToDepositToVault(vault, amountsToDeposit, address(this), true);
        vm.roll(block.number + 6);
        // State memory state1 = _getState();

        // --------------------------------------------- Hardwork
        vm.warp(block.timestamp + 12209);
        vm.roll(block.number + 17497);

        vm.prank(IPlatform(IControllable(currentStrategy).platform()).hardWorker());
        IVault(vault).doHardWork();

        // --------------------------------------------- Withdraw all
        uint maxWithdraw = IERC20(vault).balanceOf(address(this));
        _tryToWithdrawFromVault(vault, maxWithdraw, address(this));
        vm.roll(block.number + 6);
        // State memory state2 = _getState();

        vm.revertToState(snapshot);
    }

    /// @notice Deposit, check state, withdraw all, check state
    function _testDepositWithdraw(uint amountNoDecimals) internal {
        uint snapshot = vm.snapshotState();

        IStrategy strategy = IStrategy(currentStrategy);
        address vault = strategy.vault();

        // --------------------------------------------- Initial deposit (dead shares)
        uint[] memory amountsToDeposit = new uint[](1);
        amountsToDeposit[0] = 100 * 10 ** IERC20Metadata(strategy.assets()[0]).decimals();
        _tryToDepositToVault(vault, amountsToDeposit, address(1), true);

        // --------------------------------------------- Deposit
        amountsToDeposit[0] = amountNoDecimals * 10 ** IERC20Metadata(strategy.assets()[0]).decimals();

        State memory state0 = _getState();
        (, uint depositedValue) = _tryToDepositToVault(vault, amountsToDeposit, address(this), true);
        vm.roll(block.number + 6);
        State memory state1 = _getState();

        // --------------------------------------------- Withdraw all
        uint withdrawn1 = _tryToWithdrawFromVault(vault, depositedValue, address(this));
        vm.roll(block.number + 6);
        State memory state2 = _getState();

        vm.revertToState(snapshot);

        // --------------------------------------------- Check results
        assertLt(state0.strategyTotal, state1.strategyTotal, "Total should increase after deposit");
        assertEq(state2.strategyTotal, state0.strategyTotal, "Total should decrease back after withdraw all");
        assertApproxEqAbs(
            amountsToDeposit[0], withdrawn1, amountsToDeposit[0] / 1_000_000, "user should get back all assets"
        );
    }

    function _testDepositWithdrawUnderlying(uint amountNoDecimals) internal {
        uint snapshot = vm.snapshotState();

        IStrategy strategy = IStrategy(currentStrategy);
        address vault = strategy.vault();

        // --------------------------------------------- Initial deposit (dead shares)
        uint[] memory amountsToDeposit = new uint[](1);
        amountsToDeposit[0] = 100 * 10 ** IERC20Metadata(strategy.assets()[0]).decimals();
        _tryToDepositToVault(vault, amountsToDeposit, address(1), true);

        // --------------------------------------------- Deposit
        amountsToDeposit[0] = amountNoDecimals * 10 ** IERC20Metadata(strategy.assets()[0]).decimals();

        State memory state0 = _getState();
        (, uint depositedValue) = _tryToDepositToVaultUnderlying(vault, amountsToDeposit, address(this));
        vm.roll(block.number + 6);
        State memory state1 = _getState();

        // --------------------------------------------- Withdraw all
        uint withdrawn1 = _tryToWithdrawFromVaultUnderlying(vault, depositedValue, address(this));
        vm.roll(block.number + 6);
        State memory state2 = _getState();

        vm.revertToState(snapshot);

        // --------------------------------------------- Check results
        assertEq(
            state1.strategyTotal, state0.strategyTotal + amountsToDeposit[0], "Total should increase after deposit"
        );
        assertEq(state2.strategyTotal, state0.strategyTotal, "Total should decrease back after withdraw all");
        assertApproxEqAbs(
            amountsToDeposit[0],
            withdrawn1,
            amountsToDeposit[0] / 1_000_000,
            "user should get back all underlying assets"
        );

        assertEq(
            state1.underlyingStrategyBalance,
            state0.underlyingStrategyBalance + amountsToDeposit[0],
            "Underlying strategy balance should increase after deposit"
        );
        assertEq(
            state2.underlyingStrategyBalance,
            state0.underlyingStrategyBalance,
            "Underlying strategy balance should decrease back after withdraw all"
        );
    }

    function _testMaxDeposit() internal {
        IStrategy strategy = IStrategy(currentStrategy);

        // --------------------- Ensure that we cannot deposit more than maxDepositAssets
        uint[] memory tooHighAmounts = strategy.maxDepositAssets();
        tooHighAmounts[0] = tooHighAmounts[0] * 101 / 100;

        uint snapshot = vm.snapshotState();
        _tryToDepositToVault(strategy.vault(), tooHighAmounts, address(this), false);
        vm.revertToState(snapshot);

        // --------------------- Ensure that we can deposit maxDepositAssets
        snapshot = vm.snapshotState();
        uint[] memory amounts = strategy.maxDepositAssets();
        _tryToDepositToVault(strategy.vault(), amounts, address(this), true);
        vm.revertToState(snapshot);
    }
    //endregion --------------------------------- Internal functions

    //region --------------------------------- Helpers

    function _getState() internal view returns (State memory state) {
        IStrategy strategy = IStrategy(currentStrategy);
        address vault = strategy.vault();
        state.strategyTotal = strategy.total();
        state.underlyingStrategyBalance = IERC20(strategy.underlying()).balanceOf(currentStrategy);
        state.underlyingUserBalance = IERC20(strategy.underlying()).balanceOf(address(this));
        state.assetUserBalance = IERC20(strategy.assets()[0]).balanceOf(address(this));
        state.assetStrategyBalance = IERC20(strategy.assets()[0]).balanceOf(currentStrategy);
        state.userVaultBalance = IERC20(vault).balanceOf(address(this));
        state.assetVaultBalance = IERC20(strategy.assets()[0]).balanceOf(vault);

        return state;
    }

    function _tryToDepositToVault(
        address vault,
        uint[] memory amounts_,
        address user,
        bool success
    ) internal returns (uint deposited, uint values) {
        address[] memory assets = IVault(vault).assets();
        // ----------------------------- Prepare amount on user's balance
        _dealAndApprove(user, vault, assets, amounts_);
        // console.log("Deposit to vault", assets[0], amounts_[0]);

        // ----------------------------- Try to deposit assets to the vault
        uint valuesBefore = IERC20(vault).balanceOf(user);

        if (!success) {
            vm.expectRevert();
        }
        vm.prank(user);
        IStabilityVault(vault).depositAssets(assets, amounts_, 0, user);

        return (amounts_[0], IERC20(vault).balanceOf(user) - valuesBefore);
    }

    function _tryToWithdrawFromVault(address vault, uint values, address user) internal returns (uint withdrawn) {
        address[] memory _assets = IVault(vault).assets();

        uint balanceBefore = IERC20(_assets[0]).balanceOf(address(this));

        vm.prank(user);
        IStabilityVault(vault).withdrawAssets(_assets, values, new uint[](1));

        return IERC20(_assets[0]).balanceOf(user) - balanceBefore;
    }

    function _tryToDepositToVaultUnderlying(
        address vault,
        uint[] memory amounts_,
        address user
    ) internal returns (uint deposited, uint values) {
        address[] memory assets = new address[](1);
        assets[0] = IVault(vault).strategy().underlying();

        // ----------------------------- Prepare amount on user's balance
        _dealAndApprove(user, vault, assets, amounts_);
        // console.log("Deposit to vault", assets[0], amounts_[0]);

        // ----------------------------- Try to deposit assets to the vault
        uint valuesBefore = IERC20(vault).balanceOf(user);

        vm.prank(user);
        IStabilityVault(vault).depositAssets(assets, amounts_, 0, user);

        return (amounts_[0], IERC20(vault).balanceOf(user) - valuesBefore);
    }

    function _tryToWithdrawFromVaultUnderlying(
        address vault,
        uint values,
        address user
    ) internal returns (uint withdrawn) {
        address[] memory _assets = new address[](1);
        _assets[0] = IVault(vault).strategy().underlying();

        uint balanceBefore = IERC20(_assets[0]).balanceOf(address(this));

        vm.prank(user);
        IStabilityVault(vault).withdrawAssets(_assets, values, new uint[](1));

        return IERC20(_assets[0]).balanceOf(user) - balanceBefore;
    }

    function _dealAndApprove(
        address user,
        address metavault,
        address[] memory assets,
        uint[] memory amounts
    ) internal {
        for (uint j; j < assets.length; ++j) {
            deal(assets[j], user, amounts[j]);
            vm.prank(user);
            IERC20(assets[j]).approve(metavault, amounts[j]);
        }
    }
    //endregion --------------------------------- Helpers
}
