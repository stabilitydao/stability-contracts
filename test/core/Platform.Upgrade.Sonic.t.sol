// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Platform} from "../../src/core/Platform.sol";

contract PlatformUpgradeSonicTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(46366611); // Sep-10-2025 10:55:12 AM +UTC
        multisig = IPlatform(PLATFORM).multisig();
    }

    function testPlatformUpgrade() public {
        _upgrade();

        // this check mean storage is ok
        assertEq(IPlatform(PLATFORM).metaVaultFactory(), SonicConstantsLib.METAVAULT_FACTORY);
    }

    function _upgrade() internal {
        address newImplementation = address(new Platform());
        address[] memory proxies = new address[](1);
        proxies[0] = PLATFORM;
        address[] memory implementations = new address[](1);
        implementations[0] = newImplementation;
        vm.prank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.09.0-alpha", proxies, implementations);
        skip(1 days);
        vm.prank(multisig);
        IPlatform(PLATFORM).upgrade();
    }

}
