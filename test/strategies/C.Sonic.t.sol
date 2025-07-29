// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {CompoundV2Strategy} from "../../src/strategies/CompoundV2Strategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {console, Test} from "forge-std/Test.sol";

contract CompoundV2StrategyTestSonic is SonicSetup, UniversalTest {
    uint public constant FORK_BLOCK = 40578218; // Jul-28-2025 10:26:00 AM +UTC

    struct State {
        uint strategyTotal;
        uint cTokenStrategyBalance;
        uint assetUserBalance;
        uint assetStrategyBalance;
        uint userVaultBalance;
        uint assetVaultBalance;
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(FORK_BLOCK);
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
        console.log("erc7201:stability.CompoundV2Strategy");
        console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.CompoundV2Strategy")) - 1)) & ~bytes32(uint256(0xff)));
    }

    /// @notice Compare APR with https://stability.market/
    function testStrategies() public universalTest {
//        _addStrategy(SonicConstantsLib.ENCLABS_VTOKEN_USDC);
        _addStrategy(SonicConstantsLib.ENCLABS_VTOKEN_wS);
//        _addStrategy(SonicConstantsLib.ENCLABS_VTOKEN_wmetaUSD);
    }

    //region --------------------------------- Internal functions
    function _preDeposit() internal override{
        // additional tests

        // deposit - withdraw
        _testDepositWithdraw(1000);

        // todo: view functions
        // underlying, pool tvl, market, max deposit, hardworkOnDeposit and so on

        // todo: _preHardWork();

        // todo: max withdraw

        // todo: max deposit


        // todo: deposit, hardwork, withdraw, emergency
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

    /// @notice Deposit, check state, withdraw all, check state
    function _testDepositWithdraw(uint amountNoDecimals) internal {
        uint snapshot = vm.snapshotState();

        IStrategy strategy = IStrategy(currentStrategy);
        address vault = strategy.vault();

        // --------------------------------------------- Initial deposit (dead shares)
        uint[] memory amountsToDeposit = new uint[](1);
        amountsToDeposit[0] = 100 * 10 ** IERC20Metadata(strategy.assets()[0]).decimals();
        _tryToDepositToVault(vault, amountsToDeposit, address(1));

        // --------------------------------------------- Deposit
        amountsToDeposit[0] = amountNoDecimals * 10 ** IERC20Metadata(strategy.assets()[0]).decimals();

        State memory state0 = _getState();
        (uint depositedAssets, uint depositedValue) = _tryToDepositToVault(vault, amountsToDeposit, address(this));
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
            amountsToDeposit[0],
            withdrawn1,
            amountsToDeposit[0] / 1_000_000,
            "user should get back all assets"
        );
    }
    //endregion --------------------------------- Internal functions

    //region --------------------------------- Helpers

    function _getState() internal view returns (State memory state) {
        IStrategy strategy = IStrategy(currentStrategy);
        address vault = strategy.vault();
        state.strategyTotal = strategy.total();
        state.cTokenStrategyBalance = IERC20(CompoundV2Strategy(address(strategy)).market()).balanceOf(currentStrategy);
        state.assetUserBalance = IERC20(strategy.assets()[0]).balanceOf(address(this));
        state.assetStrategyBalance = IERC20(strategy.assets()[0]).balanceOf(currentStrategy);
        state.userVaultBalance = IERC20(vault).balanceOf(address(this));
        state.assetVaultBalance = IERC20(strategy.assets()[0]).balanceOf(vault);

        return state;
    }

    function _tryToDepositToVault(
        address vault,
        uint[] memory amounts_,
        address user
    ) internal returns (uint deposited, uint values) {
        address[] memory assets = IVault(vault).assets();
        // ----------------------------- Prepare amount on user's balance
        _dealAndApprove(user, vault, assets, amounts_);
        // console.log("Deposit to vault", assets[0], amounts_[0]);

        // ----------------------------- Try to deposit assets to the vault
        uint valuesBefore = IERC20(vault).balanceOf(user);

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
