// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console, Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {CVault, IVault} from "../../src/core/vaults/CVault.sol";

contract CVaultUpgradeSonicTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant VAULT1 = 0x709833e5B4B98aAb812d175510F94Bc91CFABD89;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(16633000); // Mar-28-2025 07:44:10 PM +UTC
    }

    function testCVaultUpgrade() public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address multisig = IPlatform(PLATFORM).multisig();
        IStrategy strategy = IVault(VAULT1).strategy();

        // deploy new impl and upgrade
        address vaultImplementation = address(new CVault());
        vm.prank(multisig);
        factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: VaultTypeLib.COMPOUNDING,
                implementation: vaultImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: 1e10
            })
        );

        factory.upgradeVaultProxy(VAULT1);

        uint sharesWas = IERC20(VAULT1).totalSupply();
        vm.prank(VAULT1);
        strategy.doHardWork();
        uint feeShares = IERC20(VAULT1).totalSupply() - sharesWas;
        uint feeTreasuryBal = IERC20(VAULT1).balanceOf(0xDa9c8035aA67a8cf9BF5477e0D937F74566F9039);
        assertEq(feeTreasuryBal, feeShares);
    }
}
