// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {console, Test} from "forge-std/Test.sol";

contract AaveStrategyTestSonic is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        // vm.rollFork(28237049); // May-20-2025 12:17:44 PM +UTC
        vm.rollFork(31996320); // Jun-05-2025 09:19:04 AM +UTC
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
        // console.log("erc7201:stability.AaveStrategy");
        // console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.AaveStrategy")) - 1)) & ~bytes32(uint256(0xff)));
    }

    /// @notice Compare APR with https://stability.market/
    function testAaveStrategy() public universalTest {
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_wS);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_USDC);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_scUSD);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_WETH);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_USDT);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_wOS);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_stS);
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
}
