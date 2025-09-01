// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {AaveMerklFarmStrategy} from "../../src/strategies/AaveMerklFarmStrategy.sol";
import {IAToken} from "../../src/integrations/aave/IAToken.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";
import {console, Test} from "forge-std/Test.sol";

contract AaveMerklFarmStrategyTestSonic is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(38911848); // Jul-17-2025 11:06:11 AM +UTC
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;

        console.log("erc7201:stability.AaveMerklFarmStrategy");
        console.logBytes32(
            keccak256(abi.encode(uint(keccak256("erc7201:stability.AaveMerklFarmStrategy")) - 1)) & ~bytes32(uint(0xff))
        );
    }

    struct State {
        uint aaveTotalSupply;
        uint aaveScaledTotalSupply;
        uint total;
        uint aaveTokenBalance;
        uint lastApr;
        uint lastAprCompounded;
    }

    /// @notice Compare APR with https://stability.market/
    function testAaveStrategy() public universalTest {
        //        _addStrategy(56);
        //        _addStrategy(57);
        //        _addStrategy(58);
        //        _addStrategy(59);
        _addStrategy(60);
        _addStrategy(61);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.AAVE_MERKL_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }

    function _preHardWork() internal override {
        // emulate Merkl-rewards
        deal(SonicConstantsLib.TOKEN_wS, currentStrategy, 1e18);
        deal(SonicConstantsLib.TOKEN_USDC, currentStrategy, 1e6);
    }

    function _preDeposit() internal override {
        uint snapshot = vm.snapshotState();
        AaveMerklFarmStrategy strategy = AaveMerklFarmStrategy(currentStrategy);
        address vault = strategy.vault();
        _getState(strategy, "before deposit");

        // -------------------- deposit 100
        _depositToVault(1_000e6);
        _getState(strategy, "after deposit 1000");

        // -------------------- hardwork 1 (no rewards)
        vm.warp(block.timestamp + 7 * 24 * 3600);

        vm.prank(vault);
        strategy.doHardWork();
        _getState(strategy, "after hardwork 1");

        // -------------------- deposits 200
        _depositToVault(2_000e6);
        _getState(strategy, "after deposit 2000");

        // -------------------- emulate Merkl-rewards
        deal(SonicConstantsLib.TOKEN_USDC, currentStrategy, 100e6);

        // -------------------- hardwork 2 (merkl rewards)
        vm.warp(block.timestamp + 7 * 24 * 3600);

        vm.prank(vault);
        strategy.doHardWork();
        _getState(strategy, "after hardwork 2");

        // -------------------- withdraw all
        uint balanceBefore = IVault(vault).balanceOf(address(this));
        (uint withdrawn) = _withdrawFromVault(balanceBefore);
        console.log("withdrawn", withdrawn);
        uint balanceAfter = IVault(vault).balanceOf(address(this));
        _getState(strategy, "after withdraw all");

        assertEq(balanceAfter, 0, "Vault balance should be zero after withdrawal");
        assertApproxEqAbs(
            withdrawn,
            1_000e6 + 2_000e6 + 100e6 * 70 / 100, // 30% of Merkl rewards is taken as fee
            2e6,
            "Withdrawn amount should exceed initial amount plus rewards"
        );
        assertGt(
            withdrawn,
            1_000e6 + 2_000e6 + 100e6 * 70 / 100, // 30% of Merkl rewards is taken as fee
            "Withdrawn amount should increase rewards + initial balance on earned amount"
        );

        vm.revertToState(snapshot);
    }

    /// @notice Deal doesn't work with aave tokens. So, deal the asset and mint aTokens instead.
    /// @dev https://github.com/foundry-rs/forge-std/issues/140
    function _dealUnderlying(address underlying, address to, uint amount) internal override {
        IPool pool = IPool(IAToken(underlying).POOL());

        address asset = IAToken(underlying).UNDERLYING_ASSET_ADDRESS();

        deal(asset, to, amount);

        vm.prank(to);
        IERC20(asset).approve(address(pool), amount);

        vm.prank(to);
        pool.deposit(asset, amount, to, 0);
    }

    //region -------------------------------- Internal logic
    function _getState(AaveMerklFarmStrategy strategy, string memory desc) internal view returns (State memory) {
        desc;
        IAToken aToken = IAToken(strategy.aaveToken());

        State memory state;
        state.aaveTotalSupply = aToken.totalSupply();
        state.aaveScaledTotalSupply = aToken.scaledTotalSupply();
        state.total = strategy.total();
        state.aaveTokenBalance = aToken.balanceOf(address(strategy));
        state.lastApr = strategy.lastApr();
        state.lastAprCompounded = strategy.lastAprCompound();

        //        console.log("!!!!!!!!!!!", desc);
        //        console.log("aaveTotalSupply", state.aaveTotalSupply);
        //        console.log("aaveScaledTotalSupply", state.aaveScaledTotalSupply);
        //        console.log("total", state.total);
        //        console.log("aaveTokenBalance", state.aaveTokenBalance);
        //        console.log("lastApr", state.lastApr);
        //        console.log("lastAprCompounded", state.lastAprCompounded);

        return state;
    }

    function _depositToVault(uint amount_) internal returns (uint deposited, uint values) {
        address vault = IStrategy(currentStrategy).vault();
        address[] memory assets = IVault(vault).assets();

        uint[] memory amounts_ = new uint[](assets.length);
        amounts_[0] = amount_;

        // ----------------------------- Prepare amount on user's balance
        _dealAndApprove(address(this), vault, assets, amounts_);

        // ----------------------------- Try to deposit assets to the vault
        uint valuesBefore = IERC20(vault).balanceOf(address(this));

        vm.prank(address(this));
        IStabilityVault(vault).depositAssets(assets, amounts_, 0, address(this));
        vm.roll(block.number + 6);

        return (amounts_[0], IERC20(vault).balanceOf(address(this)) - valuesBefore);
    }

    function _withdrawFromVault(uint values) internal returns (uint withdrawn) {
        address vault = IStrategy(currentStrategy).vault();
        address[] memory _assets = IVault(vault).assets();

        uint balanceBefore = IERC20(_assets[0]).balanceOf(address(this));

        vm.prank(address(this));
        IStabilityVault(vault).withdrawAssets(_assets, values, new uint[](1));
        vm.roll(block.number + 6);

        return IERC20(_assets[0]).balanceOf(address(this)) - balanceBefore;
    }

    function _dealAndApprove(address user, address spender, address[] memory assets, uint[] memory amounts) internal {
        for (uint j; j < assets.length; ++j) {
            deal(assets[j], user, amounts[j]);
            vm.prank(user);
            IERC20(assets[j]).approve(spender, amounts[j]);
        }
    }
    //endregion -------------------------------- Internal logic
}
