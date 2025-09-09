// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";
import {AvalancheSetup} from "../base/chains/AvalancheSetup.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {IAToken} from "../../src/integrations/aave/IAToken.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";
import {console, Test} from "forge-std/Test.sol";

contract AaveStrategyTestAvalanche is AvalancheSetup, UniversalTest {
    uint public constant FORK_BLOCK_C_CHAIN = 68407132; // Sep-8-2025 09:54:05 UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("AVALANCHE_RPC_URL"), FORK_BLOCK_C_CHAIN));

        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
    }

    /// @notice Compare APR with https://stability.market/
    function testAaveStrategy() public universalTest {
        _addStrategy(AvalancheConstantsLib.AAVE_aAvaUSDC);
    }

    function _addStrategy(address aToken) internal {
        address[] memory initStrategyAddresses = new address[](1);
        initStrategyAddresses[0] = aToken;
        strategies.push(
            Strategy({
                id: StrategyIdLib.AAVE,
                pool: address(0),
                farmId: type(uint).max,
                strategyInitAddresses: initStrategyAddresses,
                strategyInitNums: new uint[](0)
            })
        );
    }

    /// @notice Deal doesn't work with aave tokens. So, deal the asset and mint aTokens instead.
    /// @dev https://github.com/foundry-rs/forge-std/issues/140
    function _dealUnderlying(address underlying, address to, uint amount) internal override {
        IPool pool = IPool(IAToken(underlying).POOL());

        address asset = IAToken(underlying).UNDERLYING_ASSET_ADDRESS();
        address assetProvider = makeAddr("assetProvider");

        // amount produces amount - delta (delta ~ 1 or 2 or may be other value) of aToken on Avalanche
        // probably there is some rounding there .. let's increase source amount a bit
        uint amountToDeposit = amount * 2;
        deal(asset, assetProvider, amountToDeposit);

        vm.prank(assetProvider);
        IERC20(asset).approve(address(pool), amountToDeposit);

        vm.prank(assetProvider);
        pool.deposit(asset, amountToDeposit, assetProvider, 0);

        assertGe(IERC20(underlying).balanceOf(assetProvider), amount, "Deal enough aTokens 1");

        vm.prank(assetProvider);
        IERC20(underlying).transfer(to, amount);

        // Attempt to transfer 999121603 tokens produces 999121604 on balance on Avalanche
        // If we try to return back 1 token new balance becomes 999121602, weird behavior.
        assertApproxEqAbs(IERC20(underlying).balanceOf(to), amount, 1, "Deal enough aTokens 2");
    }
}
