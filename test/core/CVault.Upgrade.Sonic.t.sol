// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {CVault, IVault} from "../../src/core/vaults/CVault.sol";
import {Factory} from "../../src/core/Factory.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";

contract CVaultUpgradeSonicTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public constant VAULT1 = 0x709833e5B4B98aAb812d175510F94Bc91CFABD89;

    uint internal constant FORK_BLOCK = 16633000; // Mar-28-2025 07:44:10 PM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        _upgradePlatform();
    }

    function testCVaultUpgrade() public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address multisig = IPlatform(PLATFORM).multisig();
        IStrategy strategy = IVault(VAULT1).strategy();

        // deploy new impl and upgrade
        address vaultImplementation = address(new CVault());
        vm.prank(multisig);
        factory.setVaultImplementation(VaultTypeLib.COMPOUNDING, vaultImplementation);

        factory.upgradeVaultProxy(VAULT1);

        uint sharesWas = IERC20(VAULT1).totalSupply();
        vm.prank(VAULT1);
        strategy.doHardWork();
        uint feeShares = IERC20(VAULT1).totalSupply() - sharesWas;
        uint feeTreasuryBal = IERC20(VAULT1).balanceOf(0xDa9c8035aA67a8cf9BF5477e0D937F74566F9039);
        assertEq(feeTreasuryBal, feeShares);
    }

    function _upgradePlatform() internal {
        rewind(1 days);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = platform.factory();
        implementations[0] = address(new Factory());

        vm.startPrank(platform.multisig());
        platform.announcePlatformUpgrade("2025.08.21-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }
}
