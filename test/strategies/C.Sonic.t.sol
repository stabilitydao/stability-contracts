// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {console, Test} from "forge-std/Test.sol";

contract CompoundV2StrategyTestSonic is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(40578218); // Jul-28-2025 10:26:00 AM +UTC
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
        console.log("erc7201:stability.CompoundV2Strategy");
        console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.CompoundV2Strategy")) - 1)) & ~bytes32(uint256(0xff)));
    }

    /// @notice Compare APR with https://stability.market/
    function testAaveStrategy() public universalTest {
        _addStrategy(SonicConstantsLib.ENCLABS_VTOKEN_USDC);
        _addStrategy(SonicConstantsLib.ENCLABS_VTOKEN_wS);
        _addStrategy(SonicConstantsLib.ENCLABS_VTOKEN_wmetaUSD);
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
}
