// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console, Test} from "forge-std/Test.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {WrappedMetaVaultOracle} from "../../src/periphery/WrappedMetaVaultOracle.sol";
import {IAggregatorInterfaceMinimal} from "../../src/integrations/chainlink/IAggregatorInterfaceMinimal.sol";

contract WrappedMetaVaultOracleSonic is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IAggregatorInterfaceMinimal public oracle1;
    IAggregatorInterfaceMinimal public oracle2;
    IAggregatorInterfaceMinimal public oracle3;

    constructor() {
        // Jun-03-2025 08:13:07 AM +UTC
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 31528140));
        oracle1 = IAggregatorInterfaceMinimal(
            address(new WrappedMetaVaultOracle(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD))
        );
        oracle2 = IAggregatorInterfaceMinimal(
            address(new WrappedMetaVaultOracle(SonicConstantsLib.WRAPPED_METAVAULT_METAUSDC))
        );
        oracle3 = IAggregatorInterfaceMinimal(
            address(new WrappedMetaVaultOracle(SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD))
        );
    }

    function testWrappedMetaVaultOracle() public view {
        int price1 = oracle1.latestAnswer();
        int price2 = oracle2.latestAnswer();
        int price3 = oracle3.latestAnswer();
        assertGt(price1, 1e8);
        assertLt(price1, 101e6);
        //console.logInt(price1);
        assertGt(price2, 1e8);
        assertLt(price2, 101e6);
        //console.logInt(price2);
        assertGt(price3, 1e8);
        assertLt(price3, 101e6);
        //console.logInt(price3);

        assertEq(oracle1.decimals(), 8);
    }
}
