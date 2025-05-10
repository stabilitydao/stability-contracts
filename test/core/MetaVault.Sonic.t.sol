// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Test, console} from "forge-std/Test.sol";
import {
    MetaVault,
    IMetaVault,
    IStabilityVault,
    IPlatform,
    IPriceReader,
    IControllable
} from "../../src/core/vaults/MetaVault.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";

contract MetaVaultSonicTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;

    address[] public metaVaults;
    IPriceReader public priceReader;
    address public multisig;

    constructor() {
        // May-10-2025 10:38:26 AM +UTC
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 25729900));
    }

    function setUp() public {
        multisig = IPlatform(PLATFORM).multisig();
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());

        _upgradePriceReader();
        _upgradeCVaults();

        string memory vaultType;
        address[] memory vaults_;
        uint[] memory proportions_;

        metaVaults = new address[](2);

        // metaUSDC: single USDC lending vaults
        vaultType = VaultTypeLib.MULTIVAULT;
        vaults_ = new address[](5);
        vaults_[0] = SonicConstantsLib.VAULT_C_USDC_SiF;
        vaults_[1] = SonicConstantsLib.VAULT_C_USDC_S_8;
        vaults_[2] = SonicConstantsLib.VAULT_C_USDC_S_27;
        vaults_[3] = SonicConstantsLib.VAULT_C_USDC_S_34;
        vaults_[4] = SonicConstantsLib.VAULT_C_USDC_S_36;
        proportions_ = new uint[](5);
        proportions_[0] = 20e16;
        proportions_[1] = 20e16;
        proportions_[2] = 20e16;
        proportions_[3] = 20e16;
        proportions_[4] = 20e16;
        metaVaults[0] =
            _deployMetaVaultStandalone(vaultType, address(0), "Stability USDC", "metaUSDC", vaults_, proportions_);

        // metaUSD: single metavault + lending + Ichi LP vaults
        vaultType = VaultTypeLib.METAVAULT;
        vaults_ = new address[](4);
        vaults_[0] = metaVaults[0];
        vaults_[1] = SonicConstantsLib.VAULT_C_USDC_SiF;
        vaults_[2] = SonicConstantsLib.VAULT_C_USDC_scUSD_ISF_scUSD;
        vaults_[3] = SonicConstantsLib.VAULT_C_USDC_scUSD_ISF_USDC;
        proportions_ = new uint[](4);
        proportions_[0] = 50e16;
        proportions_[1] = 15e16;
        proportions_[2] = 20e16;
        proportions_[3] = 15e16;
        metaVaults[1] =
            _deployMetaVaultStandalone(vaultType, address(0), "Stability USD", "metaUSD", vaults_, proportions_);

        //console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.MetaVault")) - 1)) & ~bytes32(uint256(0xff)));
    }

    function test_universal_metavault() public {
        // test all metavaults
        for (uint i; i < metaVaults.length; ++i) {
            address metavault = metaVaults[i];
            address[] memory assets = IMetaVault(metavault).assetsForDeposit();

            // get amounts for $1000 of each
            uint[] memory depositAmounts = _getAmountsForDeposit(1000, assets);

            // previewDepositAssets
            (uint[] memory amountsConsumed, uint sharesOut,) =
                IStabilityVault(metavault).previewDepositAssets(assets, depositAmounts);

            // check previewDepositAssets return values
            assertGt(amountsConsumed[0], 0);
            assertEq(amountsConsumed.length, IMetaVault(metavault).assetsForDeposit().length);
            (uint consumedUSD,,,) = priceReader.getAssetsPrice(assets, amountsConsumed);
            assertGt(consumedUSD, 990e18);
            assertLt(consumedUSD, assets.length * 1001e18);

            // deal and approve
            _dealAndApprove(address(this), metavault, assets, depositAmounts);

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
                assets = IMetaVault(metavault).assetsForDeposit();
                depositAmounts = _getAmountsForDeposit(500, assets);
                _dealAndApprove(address(1), metavault, assets, depositAmounts);

                vm.prank(address(1));
                IStabilityVault(metavault).depositAssets(assets, depositAmounts, 0, address(1));
            }

            // test transfer and transferFrom
            vm.roll(block.number + 6);
            {
                uint user1BalanceBefore = IERC20(metavault).balanceOf(address(1));
                vm.prank(address(1));
                IERC20(metavault).transfer(address(2), user1BalanceBefore);
                assertEq(IERC20(metavault).balanceOf(address(1)), 0);
                assertGe(IERC20(metavault).balanceOf(address(2)), user1BalanceBefore - 1);
                assertLe(IERC20(metavault).balanceOf(address(2)), user1BalanceBefore);

                vm.prank(address(1));
                vm.expectRevert();
                IERC20(metavault).transferFrom(address(2), address(1), user1BalanceBefore);

                vm.roll(block.number + 6);

                vm.prank(address(2));
                IERC20(metavault).approve(address(1), user1BalanceBefore);
                assertEq(IERC20(metavault).allowance(address(2), address(1)), user1BalanceBefore);
                vm.prank(address(1));
                IERC20(metavault).transferFrom(address(2), address(1), user1BalanceBefore);
                assertEq(IERC20(metavault).balanceOf(address(2)), 0);

                // reverts
                vm.expectRevert();
                vm.prank(address(3));
                IERC20(metavault).transfer(address(0), 1);
            }

            // depositAssets | third deposit
            {
                (, sharesOut,) = IStabilityVault(metavault).previewDepositAssets(assets, depositAmounts);

                assets = IMetaVault(metavault).assetsForDeposit();
                depositAmounts = _getAmountsForDeposit(500, assets);
                _dealAndApprove(address(3), metavault, assets, depositAmounts);
                vm.prank(address(3));
                IStabilityVault(metavault).depositAssets(
                    assets, depositAmounts, sharesOut - sharesOut / 100, address(3)
                );
            }

            // flash loan protection check
            {
                uint bal = IERC20(metavault).balanceOf(address(3));

                // transfer
                vm.prank(address(3));
                vm.expectRevert(abi.encodeWithSelector(IStabilityVault.WaitAFewBlocks.selector));
                IERC20(metavault).transfer(address(10), bal);

                // deposit
                _dealAndApprove(address(3), metavault, assets, depositAmounts);
                vm.prank(address(3));
                vm.expectRevert(abi.encodeWithSelector(IStabilityVault.WaitAFewBlocks.selector));
                IStabilityVault(metavault).depositAssets(assets, depositAmounts, 0, address(3));

                // withdraw
                vm.prank(address(3));
                vm.expectRevert(abi.encodeWithSelector(IStabilityVault.WaitAFewBlocks.selector));
                IStabilityVault(metavault).withdrawAssets(assets, bal, new uint[](assets.length));
            }

            // deposit slippage check
            vm.roll(block.number + 6);
            {
                uint minSharesOut = IERC20(metavault).balanceOf(address(3));
                _dealAndApprove(address(3), metavault, assets, depositAmounts);
                vm.prank(address(3));
                vm.expectRevert();
                IStabilityVault(metavault).depositAssets(assets, depositAmounts, minSharesOut * 2, address(3));
            }

            // check proportions
            {
                uint[] memory props = IMetaVault(metavault).currentProportions();
                if (props.length == 3) {
                    assertGt(props[0], 0);
                    assertGt(props[1], 0);
                    assertGt(props[2], 0);
                }
            }

            // report
            {
                console.log(
                    string.concat(
                        IERC20Metadata(metavault).symbol(),
                        ". Name: ",
                        IERC20Metadata(metavault).name(),
                        ". Assets: ",
                        CommonLib.implodeSymbols(IStabilityVault(metavault).assets(), ", "),
                        ". Vaults: ",
                        CommonLib.implodeSymbols(IMetaVault(metavault).vaults(), ", "),
                        "."
                    )
                );

                (uint tvl,) = IStabilityVault(metavault).tvl();
                console.log(string.concat("  TVL: ", CommonLib.formatUsdAmount(tvl), "."));
            }

            // withdraw
            vm.roll(block.number + 6);
            {
                uint maxWithdraw = IMetaVault(metavault).maxWithdrawAmountTx();
                //console.log('user balance', IERC20(metavault).balanceOf(address(this)));

                //console.log('max withdraw');
                if (maxWithdraw < IERC20(metavault).balanceOf(address(this))) {
                    // revert when want withdraw more
                    vm.expectRevert(
                        abi.encodeWithSelector(
                            IMetaVault.MaxAmountForWithdrawPerTxReached.selector, maxWithdraw + 10, maxWithdraw
                        )
                    );
                    IStabilityVault(metavault).withdrawAssets(assets, maxWithdraw + 10, new uint[](assets.length));

                    // do max withdraw
                    //console.log('do max withdraw');
                    IStabilityVault(metavault).withdrawAssets(assets, maxWithdraw, new uint[](assets.length));
                    //console.log('user balance', IERC20(metavault).balanceOf(address(this)));

                    vm.roll(block.number + 6);
                }
                //console.log('max withdraw done');

                // reverts
                uint withdrawAmount = 0;
                vm.expectRevert(IControllable.IncorrectZeroArgument.selector);
                IStabilityVault(metavault).withdrawAssets(
                    assets, withdrawAmount, new uint[](assets.length), address(this), address(this)
                );

                withdrawAmount = IERC20(metavault).balanceOf(address(this));

                vm.expectRevert();
                IStabilityVault(metavault).withdrawAssets(
                    assets, withdrawAmount + 1, new uint[](assets.length), address(this), address(this)
                );

                vm.expectRevert(IControllable.IncorrectArrayLength.selector);
                IStabilityVault(metavault).withdrawAssets(
                    assets, withdrawAmount, new uint[](assets.length + 1), address(this), address(this)
                );

                if (IMetaVault(metavault).pegAsset() == address(0) && withdrawAmount < 1e13) {
                    vm.expectRevert(
                        abi.encodeWithSelector(IMetaVault.UsdAmountLessThreshold.selector, withdrawAmount, 1e13)
                    );
                    IStabilityVault(metavault).withdrawAssets(
                        assets, withdrawAmount, new uint[](assets.length), address(this), address(this)
                    );
                } else {
                    //address vaultForWithdraw = IMetaVault(metavault).vaultForWithdraw();
                    IStabilityVault(metavault).withdrawAssets(
                        assets, withdrawAmount, new uint[](assets.length), address(this), address(this)
                    );
                }
            }
        }
    }

    function test_metavault_management() public {
        IMetaVault metavault = IMetaVault(metaVaults[0]);

        // setName, setSymbol
        vm.expectRevert(IControllable.NotOperator.selector);
        metavault.setName("new name");
        vm.prank(multisig);
        metavault.setName("new name");
        assertEq(IERC20Metadata(address(metavault)).name(), "new name");
        vm.prank(multisig);
        metavault.setSymbol("new symbol");
        assertEq(IERC20Metadata(address(metavault)).symbol(), "new symbol");

        // change proportions
        uint[] memory newTargetProportions = new uint[](2);
        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        metavault.setTargetProportions(newTargetProportions);
        newTargetProportions = new uint[](5);
        vm.expectRevert(IMetaVault.IncorrectProportions.selector);
        metavault.setTargetProportions(newTargetProportions);
        newTargetProportions[0] = 2e17;
        newTargetProportions[1] = 3e17;
        newTargetProportions[2] = 5e17;
        vm.expectRevert(IControllable.IncorrectMsgSender.selector);
        metavault.setTargetProportions(newTargetProportions);
        vm.prank(multisig);
        metavault.setTargetProportions(newTargetProportions);
        assertEq(metavault.targetProportions()[2], newTargetProportions[2]);

        // add vault
        address vault = SonicConstantsLib.VAULT_C_USDC_scUSD_ISF_scUSD;
        newTargetProportions = new uint[](3);

        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        metavault.addVault(vault, newTargetProportions);

        vm.startPrank(multisig);
        vm.expectRevert(IMetaVault.IncorrectVault.selector);
        metavault.addVault(vault, newTargetProportions);

        vault = SonicConstantsLib.VAULT_C_USDC_S_49;
        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        metavault.addVault(vault, newTargetProportions);

        newTargetProportions = new uint[](6);
        vm.expectRevert(IMetaVault.IncorrectProportions.selector);
        metavault.addVault(vault, newTargetProportions);

        newTargetProportions[0] = 1e18;
        vault = SonicConstantsLib.VAULT_C_USDC_S_8;
        vm.expectRevert(IMetaVault.IncorrectVault.selector);
        metavault.addVault(vault, newTargetProportions);

        vault = SonicConstantsLib.VAULT_C_USDC_S_49;
        metavault.addVault(vault, newTargetProportions);
        vm.stopPrank();

        assertEq(IMetaVault(metavault).vaults()[5], SonicConstantsLib.VAULT_C_USDC_S_49);
    }

    function test_metavault_view_methods() public view {
        IMetaVault metavault = IMetaVault(metaVaults[0]);
        assertEq(metavault.pegAsset(), address(0));
        (uint price, bool trusted) = metavault.price();
        assertEq(price, 1e18);
        assertEq(trusted, true);
        assertEq(metavault.vaults().length, 5);
        assertEq(metavault.assets().length, 1);
        assertEq(metavault.totalSupply(), 0);
        assertEq(metavault.balanceOf(address(this)), 0);
        assertEq(metavault.targetProportions().length, 5);
        assertEq(metavault.targetProportions()[0], 20e16);
        assertEq(metavault.currentProportions().length, 5);
        assertEq(metavault.currentProportions()[0], 20e16);
        assertEq(metavault.vaultForDeposit(), SonicConstantsLib.VAULT_C_USDC_SiF);
        (uint tvl,) = metavault.tvl();
        assertEq(tvl, 0);
        assertEq(IERC20Metadata(address(metavault)).name(), "Stability USDC");
        assertEq(IERC20Metadata(address(metavault)).symbol(), "metaUSDC");
        assertEq(IERC20Metadata(address(metavault)).decimals(), 18);

        assertEq(metavault.vaultForWithdraw(), metavault.vaults()[0]);
        assertEq(metavault.vaultType(), VaultTypeLib.MULTIVAULT);
    }

    function _upgradePriceReader() internal {
        address[] memory proxies = new address[](1);
        proxies[0] = address(priceReader);
        address[] memory implementations = new address[](1);
        implementations[0] = address(new PriceReader());
        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.05.0-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
        vm.stopPrank();
    }

    function _upgradeCVaults() internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

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

        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_SiF);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_scUSD_ISF_scUSD);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_scUSD_ISF_USDC);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_8);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_27);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_34);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_36);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_49);
    }

    function _deployMetaVaultStandalone(
        string memory type_,
        address pegAsset,
        string memory name_,
        string memory symbol_,
        address[] memory vaults_,
        uint[] memory proportions_
    ) internal returns (address metaVaultProxy) {
        MetaVault implementation = new MetaVault();
        Proxy proxy = new Proxy();
        proxy.initProxy(address(implementation));
        MetaVault(address(proxy)).initialize(PLATFORM, type_, pegAsset, name_, symbol_, vaults_, proportions_);
        return address(proxy);
    }

    function _getAmountsForDeposit(
        uint usdValue,
        address[] memory assets
    ) internal view returns (uint[] memory depositAmounts) {
        depositAmounts = new uint[](assets.length);
        for (uint j; j < assets.length; ++j) {
            (uint price,) = priceReader.getPrice(assets[j]);
            require(price > 0, "UniversalTest: price is zero. Forget to add swapper routes?");
            depositAmounts[j] = usdValue * 10 ** IERC20Metadata(assets[j]).decimals() * 1e18 / price;
        }
    }

    function _dealAndApprove(
        address user,
        address metavault,
        address[] memory assets,
        uint[] memory amounts
    ) internal {
        for (uint j; j < assets.length; ++j) {
            deal(assets[j], user, amounts[j]);
            vm.prank(user);
            IERC20(assets[j]).approve(metavault, amounts[j]);
        }
    }
}
