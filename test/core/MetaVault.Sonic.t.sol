// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Test, console} from "forge-std/Test.sol";
import {MetaVault, IMetaVault, IStabilityVault, IPlatform, IPriceReader} from "../../src/core/vaults/MetaVault.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";

contract MetaVaultSonicTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant VAULT_C_USDC_SiF = 0xa51e7204054464e656B3658e7dBb63d9b0f150f1;
    address public constant VAULT_C_USDC_scUSD_ISF_scUSD = 0x8C64D2a1960C7B4b22Dbb367D2D212A21E75b942;
    address public constant VAULT_C_USDC_scUSD_ISF_USDC = 0xb773B791F3baDB3b28BC7A2da18E2a012b9116c2;

    address[] public metaVaults;
    IPriceReader public priceReader;

    constructor() {
        // Apr-21-2025 03:25:38 AM +UTC
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 21300000));
    }

    function setUp() public {
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        address[] memory vaults_;
        uint[] memory proportions_;

        metaVaults = new address[](1);

        // metaUSD with single lending + 2 Ichi LP vaults
        vaults_ = new address[](3);
        vaults_[0] = VAULT_C_USDC_SiF;
        vaults_[1] = VAULT_C_USDC_scUSD_ISF_scUSD;
        vaults_[2] = VAULT_C_USDC_scUSD_ISF_USDC;
        proportions_ = new uint[](3);
        proportions_[0] = 50e16;
        proportions_[1] = 30e16;
        proportions_[2] = 20e16;
        metaVaults[0] = _deployMetaVaultStandalone(address(0), "Stability metaUSD", "metaUSD", vaults_, proportions_);

        //console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.MetaVault")) - 1)) & ~bytes32(uint256(0xff)));
    }

    function test_universal_metavault() public {
        // test all metavaults
        for (uint i; i < metaVaults.length; ++i) {
            address metavault = metaVaults[i];
            address[] memory assets = IMetaVault(metavault).targetAssets();

            // get amounts for $1000 of each
            uint[] memory depositAmounts = new uint[](assets.length);
            for (uint j; j < assets.length; ++j) {
                (uint price,) = priceReader.getPrice(assets[j]);
                require(price > 0, "UniversalTest: price is zero. Forget to add swapper routes?");
                depositAmounts[j] = 1000 * 10 ** IERC20Metadata(assets[j]).decimals() * 1e18 / price;
            }

            // previewDepositAssets
            (uint[] memory amountsConsumed, uint sharesOut, uint valueOut) =
                IStabilityVault(metavault).previewDepositAssets(assets, depositAmounts);

            // check previewDepositAssets return values
            assertGt(amountsConsumed[0], 0);
            assertEq(amountsConsumed.length, IMetaVault(metavault).targetAssets().length);
            (uint consumedUSD,,,) = priceReader.getAssetsPrice(assets, amountsConsumed);
            assertGt(consumedUSD, 990e18);
            assertLt(consumedUSD, assets.length * 1001e18);

            // deal and approve
            for (uint j; j < assets.length; ++j) {
                deal(assets[j], address(this), depositAmounts[j]);
                IERC20(assets[j]).approve(metavault, depositAmounts[j]);

                // user address(1)
                deal(assets[j], address(1), depositAmounts[j] / 2);
                vm.prank(address(1));
                IERC20(assets[j]).approve(metavault, depositAmounts[j] / 2);
            }

            // depositAssets | first deposit
            IStabilityVault(metavault).depositAssets(assets, depositAmounts, sharesOut - 10000, address(this));

            // check state after first deposit
            {
                uint balance = IERC20(metavault).balanceOf(address(this));
                assertGt(balance, consumedUSD * 999 / 1000);
                assertLt(balance, consumedUSD * 1001 / 1000);
                if (IMetaVault(metavault).pegAsset() == address(0)) {
                    assertEq(balance, IERC20(metavault).totalSupply());
                }
            }

            // depositAssets | second deposit
            {
                uint[] memory depositAmounts2 = new uint[](assets.length);
                for (uint j; j < assets.length; ++j) {
                    depositAmounts2[j] = depositAmounts[j] / 2;
                }
                vm.prank(address(1));
                IStabilityVault(metavault).depositAssets(assets, depositAmounts2, 0, address(1));
            }
        }
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
        assertEq(metavault.targetVault(), VAULT_C_USDC_SiF);
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
