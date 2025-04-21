// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {MetaVault, IMetaVault} from "../../src/core/vaults/MetaVault.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";

contract MetaVaultSonicTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant VAULT_C_USDC_SiF = 0xa51e7204054464e656B3658e7dBb63d9b0f150f1;
    address public constant VAULT_C_USDC_scUSD_ISF_scUSD = 0x8C64D2a1960C7B4b22Dbb367D2D212A21E75b942;
    address public constant VAULT_C_USDC_scUSD_ISF_USDC = 0xb773B791F3baDB3b28BC7A2da18E2a012b9116c2;

    address[] public metaVaults;

    constructor() {
        // Apr-21-2025 03:25:38 AM +UTC
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 21300000));
    }

    function setUp() public {
        uint len = 3;
        address[] memory vaults_ = new address[](len);
        vaults_[0] = VAULT_C_USDC_SiF;
        vaults_[1] = VAULT_C_USDC_scUSD_ISF_scUSD;
        vaults_[2] = VAULT_C_USDC_scUSD_ISF_USDC;
        uint[] memory proportions_ = new uint[](len);
        proportions_[0] = 50e16;
        proportions_[1] = 30e16;
        proportions_[2] = 20e16;
        metaVaults = new address[](1);
        metaVaults[0] =
            _deployMetaVaultStandalone(address(0), "Stability metaUSD stablecoin", "metaUSD", vaults_, proportions_);

        //console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.MetaVault")) - 1)) & ~bytes32(uint256(0xff)));
    }

    function test_empty_metavault() public view {
        IMetaVault metavault = IMetaVault(metaVaults[0]);
        assertEq(metavault.pegAsset(), address(0));
        (uint price, bool trusted) = metavault.price();
        assertEq(price, 1e18);
        assertEq(trusted, true);
        assertEq(metavault.vaults().length, 3);
        assertEq(metavault.assets().length, 2);
        assertEq(metavault.totalSupply(), 0);
        assertEq(metavault.balanceOf(address(this)), 0);
        assertEq(metavault.targetProportions().length, 3);
        assertEq(metavault.targetProportions()[0], 50e16);
        assertEq(metavault.currentProportions().length, 3);
        assertEq(metavault.currentProportions()[0], 50e16);
        assertEq(metavault.targetVault(), 0xa51e7204054464e656B3658e7dBb63d9b0f150f1);
        (uint tvl,) = metavault.tvl();
        assertEq(tvl, 0);
    }

    function _deployMetaVaultStandalone(
        address pegAsset,
        string memory name_,
        string memory symbol_,
        address[] memory vaults_,
        uint[] memory proportions_
    ) internal returns (address metaVaultProxy) {
        MetaVault implementation = new MetaVault();
        Proxy proxy = new Proxy();
        proxy.initProxy(address(implementation));
        MetaVault(address(proxy)).initialize(PLATFORM, pegAsset, name_, symbol_, vaults_, proportions_);
        return address(proxy);
    }
}
