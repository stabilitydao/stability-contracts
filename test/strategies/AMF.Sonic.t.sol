// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
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
        console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.AaveMerklFarmStrategy")) - 1)) & ~bytes32(uint256(0xff)));
    }

    /// @notice Compare APR with https://stability.market/
    function testAaveStrategy() public universalTest {
        _addStrategy(56);
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
        deal(SonicConstantsLib.TOKEN_wS, currentStrategy, 30e18);
        deal(SonicConstantsLib.TOKEN_USDC, currentStrategy, 1e18);
    }
}
