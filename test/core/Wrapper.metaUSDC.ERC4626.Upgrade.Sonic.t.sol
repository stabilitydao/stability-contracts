// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC4626UniversalTest, IERC4626} from "../base/ERC4626Test.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";

contract WrapperERC4626SonicTest is ERC4626UniversalTest {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVaultFactory public metaVaultFactory;

    function setUp() public override {
        ERC4626UniversalTest.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "sonic";
        overrideBlockNumber = 27965000;

        // Stability USDC
        wrapper = IERC4626(SonicConstantsLib.WRAPPED_METAVAULT_metaUSDC);
        // Donor of USDC.e
        underlyingDonor = 0x578Ee1ca3a8E1b54554Da1Bf7C583506C4CD11c6;
        amountToDonate = 1e6 * 1e6;
    }

    function _upgradeThings() internal override {
        multisig = IPlatform(PLATFORM).multisig();
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());

        address newMetaVaultImplementation = address(new MetaVault());
        address newWrapperImplementation = address(new WrappedMetaVault());
        vm.startPrank(multisig);
        metaVaultFactory.setMetaVaultImplementation(newMetaVaultImplementation);
        metaVaultFactory.setWrappedMetaVaultImplementation(newWrapperImplementation);
        address[] memory proxies = new address[](2);
        proxies[0] = SonicConstantsLib.METAVAULT_metaUSDC;
        proxies[1] = SonicConstantsLib.WRAPPED_METAVAULT_metaUSDC;
        metaVaultFactory.upgradeMetaProxies(proxies);
        address[] memory vaults = IMetaVault(SonicConstantsLib.METAVAULT_metaUSDC).vaults();
        for (uint i; i < vaults.length; ++i) {
            IVault(vaults[i]).setDoHardWorkOnDeposit(false);
        }
        vm.stopPrank();
    }
}
