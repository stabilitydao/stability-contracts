// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";
import {AvalancheSetup} from "../base/chains/AvalancheSetup.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {IAToken} from "../../src/integrations/aave/IAToken.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";
// import {console, Test} from "forge-std/Test.sol";

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

        deal(asset, to, amount);

        vm.prank(to);
        IERC20(asset).approve(address(pool), amount);

        vm.prank(to);
        pool.deposit(asset, amount, to, 0);
    }
}
