// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PlasmaSetup, PlasmaConstantsLib} from "../base/chains/PlasmaSetup.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {AaveMerklFarmStrategy} from "../../src/strategies/AaveMerklFarmStrategy.sol";
import {IAToken} from "../../src/integrations/aave/IAToken.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";
import {console} from "forge-std/Test.sol";

contract AaveMerklFarmStrategyPlasmaTest is PlasmaSetup, UniversalTest {
    uint public constant FORK_BLOCK = 2196726; // Sep-29-2025 06:05:08 UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("PLASMA_RPC_URL"), FORK_BLOCK));
        makePoolVolumePriceImpactTolerance = 9_000;

        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
    }

    function testAaveStrategy() public universalTest {
        _addStrategy(0);
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
        deal(PlasmaConstantsLib.TOKEN_WXPL, currentStrategy, 1e18);
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

        console.log("TODO: fix deposit of underlying, balance underlying:", IERC20(underlying).balanceOf(to));
    }

    //region -------------------------------- Internal logic
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
