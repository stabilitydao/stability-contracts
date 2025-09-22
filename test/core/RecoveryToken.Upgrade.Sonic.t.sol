// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IRecoveryToken} from "../../src/interfaces/IRecoveryToken.sol";
import {RecoveryToken} from "../../src/core/vaults/RecoveryToken.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Test} from "forge-std/Test.sol";

contract RecoveryTokenUpgradeSonicTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    uint public constant FORK_BLOCK = 45824977; // Sep-05-2025 08:48:17 AM +UTC

    IFactory public factory;
    address public multisig;

    address public constant HOLDER_REC_WMETA_USDC = 0xCE785cccAa0c163E6f83b381eBD608F98f694C44;
    address public constant HOLDER_REC_WMETA_SCUSD = 0xCE785cccAa0c163E6f83b381eBD608F98f694C44;
    address public constant HOLDER_REC_META_USD = 0x8901D9cf0272A2876525ee25Fcbb9E423c4B95f6;

    struct TestCase {
        address holder;
        address recoveryToken;
        uint8 oldDecimals;
        uint8 newDecimals;
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();
    }

    function fixtureTestData() public pure returns (TestCase[] memory) {
        TestCase[] memory testCases = new TestCase[](3);
        testCases[0] = TestCase({
            holder: HOLDER_REC_WMETA_USDC,
            recoveryToken: SonicConstantsLib.RECOVERY_TOKEN_CREDIX_WMETAUSDC,
            oldDecimals: 18,
            newDecimals: 6
        });
        testCases[1] = TestCase({
            holder: HOLDER_REC_WMETA_SCUSD,
            recoveryToken: SonicConstantsLib.RECOVERY_TOKEN_CREDIX_WMETASCUSD,
            oldDecimals: 18,
            newDecimals: 6
        });
        testCases[2] = TestCase({
            holder: HOLDER_REC_META_USD,
            recoveryToken: SonicConstantsLib.RECOVERY_TOKEN_CREDIX_METAUSD,
            oldDecimals: 18,
            newDecimals: 18
        });
        return testCases;
    }

    function tableDecimalsTest(TestCase memory testData) public {
        _upgradeRecoveryToken(testData.recoveryToken);

        IRecoveryToken recoveryToken = IRecoveryToken(testData.recoveryToken);

        uint balanceBefore = IERC20(testData.recoveryToken).balanceOf(testData.holder);
        assertTrue(balanceBefore != 0, "balanceBefore > 0");
        assertEq(IERC20Metadata(testData.recoveryToken).decimals(), testData.oldDecimals, "old decimals");

        // -------------------- Try to set decimals as non-multisig
        vm.expectRevert();
        vm.prank(address(this));
        recoveryToken.setDecimals(testData.newDecimals);

        // -------------------- Change decimals and change results
        vm.prank(multisig);
        recoveryToken.setDecimals(testData.newDecimals);

        uint balanceAfter = IERC20(testData.recoveryToken).balanceOf(testData.holder);

        assertEq(balanceAfter, balanceBefore, "balance wasn't changed");
        assertEq(IERC20Metadata(testData.recoveryToken).decimals(), testData.newDecimals, "new decimals");
    }

    //region ---------------------------------- Helpers
    function _upgradeRecoveryToken(address recoveryToken_) internal {
        IMetaVaultFactory metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);

        address vaultImplementation = address(new RecoveryToken());

        vm.prank(multisig);
        metaVaultFactory.setRecoveryTokenImplementation(vaultImplementation);

        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(recoveryToken_);

        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);
    }

    //endregion ---------------------------------- Helpers
}
