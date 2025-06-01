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

contract WrapperERC4626scUSDSonicTest is ERC4626UniversalTest {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVaultFactory public metaVaultFactory;

    function setUp() public override {
        ERC4626UniversalTest.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "sonic";
        overrideBlockNumber = 30141969;

        // Stability scUSD
        wrapper = IERC4626(SonicConstantsLib.WRAPPED_METAVAULT_metascUSD);
        // Donor of USDC.e
        underlyingDonor = 0xe6605932e4a686534D19005BB9dB0FBA1F101272;
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
        proxies[0] = SonicConstantsLib.METAVAULT_metascUSD;
        proxies[1] = SonicConstantsLib.WRAPPED_METAVAULT_metascUSD;
        metaVaultFactory.upgradeMetaProxies(proxies);
        vm.stopPrank();
    }
}
