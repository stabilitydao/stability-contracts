// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    MetaVault,
    IMetaVault,
    IStabilityVault,
    IPlatform,
    IPriceReader,
    IControllable
} from "../../src/core/vaults/MetaVault.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
// import {MetaVaultFactory} from "../../src/core/MetaVaultFactory.sol";
import {Platform} from "../../src/core/Platform.sol";
// import {PriceReader} from "../../src/core/PriceReader.sol";
// import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SiloManagedFarmStrategy} from "../../src/strategies/SiloManagedFarmStrategy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Test, console} from "forge-std/Test.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";
import {SiloFarmStrategy} from "../../src/strategies/SiloFarmStrategy.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";
import {IchiSwapXFarmStrategy} from "../../src/strategies/IchiSwapXFarmStrategy.sol";

contract MetaVaultSonicTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVaultFactory public metaVaultFactory;
    address[] public metaVaults;
    IPriceReader public priceReader;
    address public multisig;

    constructor() {
        // May-14-2025 10:14:19 PM +UTC
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 26834601));
    }

    function setUp() public {
        multisig = IPlatform(PLATFORM).multisig();
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);

        // _upgradePriceReader();
        _upgradeCVaultsAndStrategies();
        //_deployMetaVaultFactory();
        // _upgradePlatform();
        _setupMetaVaultFactory();
        _setupImplementations();

        string memory vaultType;
        address[] memory vaults_;
        uint[] memory proportions_;

        metaVaults = new address[](2);

        // metaUSDC: single USDC lending vaults
        vaultType = VaultTypeLib.MULTIVAULT;
        vaults_ = new address[](5);
        vaults_[0] = SonicConstantsLib.VAULT_C_USDC_SIF;
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
        metaVaults[0] = _deployMetaVaultByMetaVaultFactory(
            vaultType, SonicConstantsLib.TOKEN_USDC, "Stability USDC", "metaUSDC", vaults_, proportions_
        );
        _deployWrapper(metaVaults[0]);

        // metaUSD: single metavault + lending + Ichi LP vaults
        vaultType = VaultTypeLib.METAVAULT;
        vaults_ = new address[](4);
        vaults_[0] = metaVaults[0];
        vaults_[1] = SonicConstantsLib.VAULT_C_USDC_SIF;
        vaults_[2] = SonicConstantsLib.VAULT_C_USDC_SCUSD_ISF_SCUSD;
        vaults_[3] = SonicConstantsLib.VAULT_C_USDC_SCUSD_ISF_USDC;
        proportions_ = new uint[](4);
        proportions_[0] = 50e16;
        proportions_[1] = 15e16;
        proportions_[2] = 20e16;
        proportions_[3] = 15e16;
        metaVaults[1] =
            _deployMetaVaultByMetaVaultFactory(vaultType, address(0), "Stability USD", "metaUSD", vaults_, proportions_);
        _deployWrapper(metaVaults[1]);

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
            IStabilityVault(metavault).depositAssets(assets, depositAmounts, sharesOut * 9999 / 10000, address(this));

            // check state after first deposit
            {
                uint balance = IERC20(metavault).balanceOf(address(this));
                assertGt(balance, consumedUSD * 999 / 1000);
                assertLt(balance, consumedUSD * 1001 / 1000);
                if (IMetaVault(metavault).pegAsset() == address(0)) {
                    assertEq(balance, IERC20(metavault).totalSupply());
                }
                (uint sharePrice,,,) = IMetaVault(metavault).internalSharePrice();
                assertGt(sharePrice, 9e17);
                assertLt(sharePrice, 11e17);
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
                /// forge-lint: disable-next-line
                IERC20(metavault).transfer(address(2), user1BalanceBefore);
                assertLe(IERC20(metavault).balanceOf(address(1)), 1, "mv-u-1");
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
                assertEq(IERC20(metavault).balanceOf(address(2)), 0, "mv-u-2");

                // reverts
                vm.expectRevert();
                vm.prank(address(3));
                /// forge-lint: disable-next-line
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
                /// forge-lint: disable-next-line
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
            {
                vm.roll(block.number + 6);
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

            vm.warp(block.timestamp + 600);
            skip(600);

            // report
            {
                vm.prank(multisig);
                (uint sharePrice, int apr,, uint duration) = IMetaVault(metavault).emitAPR();
                assertGt(sharePrice, 9999e14);
                assertLt(sharePrice, 10001e14);

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
                console.log(
                    string.concat(
                        "  TVL: ",
                        CommonLib.formatUsdAmount(tvl),
                        ". APR: ",
                        CommonLib.formatAprInt(apr),
                        ". Duration: ",
                        Strings.toString(duration)
                    )
                );

                (uint liveSharePrice,,,) = IMetaVault(metavault).internalSharePrice();
                assertEq(liveSharePrice, sharePrice);
            }

            // rebalance
            {
                if (CommonLib.eq(IStabilityVault(metavault).vaultType(), VaultTypeLib.MULTIVAULT)) {
                    uint[] memory proportions = IMetaVault(metavault).currentProportions();
                    if (proportions.length == 5) {
                        uint[] memory withdrawShares = new uint[](5);
                        withdrawShares[0] = IERC20(IMetaVault(metavault).vaults()[0]).balanceOf(metavault) / 10;
                        withdrawShares[1] = IERC20(IMetaVault(metavault).vaults()[0]).balanceOf(metavault) / 3;
                        withdrawShares[2] = IERC20(IMetaVault(metavault).vaults()[2]).balanceOf(metavault) / 4;
                        uint[] memory depositAmountsProportions = new uint[](5);
                        depositAmountsProportions[3] = 4e17;
                        depositAmountsProportions[4] = 6e17;
                        vm.expectRevert(IControllable.IncorrectMsgSender.selector);
                        IMetaVault(metavault).rebalance(withdrawShares, depositAmountsProportions);

                        vm.prank(multisig);
                        IMetaVault(metavault).rebalance(withdrawShares, depositAmountsProportions);
                        proportions = IMetaVault(metavault).currentProportions();
                    }
                }
            }

            // withdraw
            {
                vm.roll(block.number + 6);

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
                    IStabilityVault(metavault).withdrawAssets(assets, maxWithdraw, new uint[](assets.length));

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

                if (
                    (
                        IMetaVault(metavault).pegAsset() == address(0)
                            || IMetaVault(metavault).pegAsset() == SonicConstantsLib.TOKEN_USDC
                    ) && withdrawAmount < 1e16
                ) {
                    vm.expectRevert(
                        /*
                        abi.encodeWithSelector(IMetaVault.UsdAmountLessThreshold.selector, withdrawAmount, 1e13)
                              */
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

            // use wrapper
            {
                address user = address(10);
                address wrapper = metaVaultFactory.wrapper(metavault);
                _dealAndApprove(user, metavault, assets, depositAmounts);
                vm.startPrank(user);

                if (CommonLib.eq(IStabilityVault(metavault).vaultType(), VaultTypeLib.METAVAULT)) {
                    IStabilityVault(metavault).depositAssets(assets, depositAmounts, 0, user);
                    vm.roll(block.number + 6);
                    uint bal = IERC20(metavault).balanceOf(user);
                    IERC20(metavault).approve(wrapper, bal);
                    IWrappedMetaVault(wrapper).deposit(bal, user);
                    uint wrapperSharesBal = IERC20(wrapper).balanceOf(user);
                    assertGt(wrapperSharesBal, 0);

                    assertGt(IERC4626(wrapper).totalAssets(), 0);

                    vm.roll(block.number + 6);
                    IWrappedMetaVault(wrapper).redeem(wrapperSharesBal, user, user);
                }

                if (CommonLib.eq(IStabilityVault(metavault).vaultType(), VaultTypeLib.MULTIVAULT)) {
                    uint bal = IERC20(assets[0]).balanceOf(user);
                    IERC20(assets[0]).approve(wrapper, bal);
                    IWrappedMetaVault(wrapper).deposit(bal, user);
                    uint wrapperSharesBal = IERC20(wrapper).balanceOf(user);
                    assertGt(wrapperSharesBal, 0);
                    assertGt(IERC4626(wrapper).totalAssets(), 0);

                    vm.roll(block.number + 100);
                    vm.warp(block.timestamp + 100);

                    uint toAssets = IERC4626(wrapper).convertToAssets(wrapperSharesBal);
                    assertGt(toAssets, bal);

                    uint maxWithdraw = IERC4626(wrapper).maxWithdraw(user);
                    IWrappedMetaVault(wrapper).redeem(
                        Math.min(wrapperSharesBal, IERC4626(wrapper).maxRedeem(user)), user, user
                    );
                    uint newAssetBal = IERC20(assets[0]).balanceOf(user);
                    assertGe(newAssetBal + 1, Math.min(bal, maxWithdraw), "mv-u-2.5");
                    assertLt(newAssetBal, bal * 1001 / 1000, "mv-u-2.6");
                    assertLe(IERC20(wrapper).balanceOf(user), bal / 10000, "mv-u-3");
                }
                vm.stopPrank();
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

        vm.expectRevert(IControllable.IncorrectMsgSender.selector);
        metavault.setTargetProportions(newTargetProportions);

        vm.startPrank(multisig);

        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        metavault.setTargetProportions(newTargetProportions);
        newTargetProportions = new uint[](5);
        vm.expectRevert(IMetaVault.IncorrectProportions.selector);
        metavault.setTargetProportions(newTargetProportions);
        newTargetProportions[0] = 2e17;
        newTargetProportions[1] = 3e17;
        newTargetProportions[2] = 5e17;
        metavault.setTargetProportions(newTargetProportions);
        assertEq(metavault.targetProportions()[2], newTargetProportions[2]);
        vm.stopPrank();

        // add vault
        address vault = SonicConstantsLib.VAULT_C_USDC_SCUSD_ISF_SCUSD;
        newTargetProportions = new uint[](3);

        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        metavault.addVault(vault, newTargetProportions);

        vm.startPrank(multisig);

        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        metavault.addVault(vault, newTargetProportions);

        newTargetProportions = new uint[](6);

        vm.expectRevert(IMetaVault.IncorrectProportions.selector);
        metavault.addVault(vault, newTargetProportions);

        newTargetProportions[0] = 1e18;
        vault = SonicConstantsLib.VAULT_C_USDC_S_8;
        vm.expectRevert(IMetaVault.IncorrectVault.selector);
        metavault.addVault(vault, newTargetProportions);

        vm.expectRevert(IMetaVault.IncorrectVault.selector);
        metavault.addVault(vault, newTargetProportions);

        vault = SonicConstantsLib.VAULT_C_USDC_S_49;
        metavault.addVault(vault, newTargetProportions);
        vm.stopPrank();

        assertEq(IMetaVault(metavault).vaults()[5], SonicConstantsLib.VAULT_C_USDC_S_49);
    }

    function test_metavault_view_methods() public view {
        IMetaVault metavault = IMetaVault(metaVaults[0]);
        assertEq(metavault.pegAsset(), SonicConstantsLib.TOKEN_USDC);
        (uint price, bool trusted) = metavault.price();
        assertLt(price, 101e16);
        assertGt(price, 99e16);
        assertEq(trusted, true);
        assertEq(metavault.vaults().length, 5);
        assertEq(metavault.assets().length, 1);
        assertEq(metavault.totalSupply(), 0);
        assertEq(metavault.balanceOf(address(this)), 0);
        assertEq(metavault.targetProportions().length, 5);
        assertEq(metavault.targetProportions()[0], 20e16);
        assertEq(metavault.currentProportions().length, 5);
        assertEq(metavault.currentProportions()[0], 20e16);
        assertEq(metavault.vaultForDeposit(), SonicConstantsLib.VAULT_C_USDC_SIF);
        (uint tvl,) = metavault.tvl();
        assertEq(tvl, 0);
        assertEq(IERC20Metadata(address(metavault)).name(), "Stability USDC");
        assertEq(IERC20Metadata(address(metavault)).symbol(), "metaUSDC");
        assertEq(IERC20Metadata(address(metavault)).decimals(), 18);

        assertEq(metavault.vaultForWithdraw(), metavault.vaults()[0]);
        assertEq(metavault.vaultType(), VaultTypeLib.MULTIVAULT);
    }

    /*function _upgradePriceReader() internal {
        address[] memory proxies = new address[](1);
        proxies[0] = address(priceReader);
        address[] memory implementations = new address[](1);
        implementations[0] = address(new PriceReader());
        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.05.0-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
        vm.stopPrank();
    }*/

    //region ------------------------------------ Upgrade CVaults and strategies
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

        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_SIF);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_SCUSD_ISF_SCUSD);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_SCUSD_ISF_USDC);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_8);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_27);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_34);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_36);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_49);
    }

    function _upgradeCVaultsAndStrategies() internal {
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

        address[8] memory vaults = [
            SonicConstantsLib.VAULT_C_USDC_SIF,
            SonicConstantsLib.VAULT_C_USDC_S_8,
            SonicConstantsLib.VAULT_C_USDC_S_27,
            SonicConstantsLib.VAULT_C_USDC_S_34,
            SonicConstantsLib.VAULT_C_USDC_S_36,
            SonicConstantsLib.VAULT_C_USDC_S_49,
            SonicConstantsLib.VAULT_C_USDC_SCUSD_ISF_SCUSD,
            SonicConstantsLib.VAULT_C_USDC_SCUSD_ISF_USDC
        ];

        for (uint i; i < vaults.length; i++) {
            factory.upgradeVaultProxy(vaults[i]);
            if (CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.SILO)) {
                _upgradeSiloStrategy(address(IVault(payable(vaults[i])).strategy()));
            } else if (CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.SILO_FARM)) {
                _upgradeSiloFarmStrategy(address(IVault(payable(vaults[i])).strategy()));
            } else if (
                CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.SILO_MANAGED_FARM)
            ) {
                _upgradeSiloManagedFarmStrategy(address(IVault(payable(vaults[i])).strategy()));
            } else if (
                CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.ICHI_SWAPX_FARM)
            ) {
                _upgradeIchiSwapxFarmStrategy(address(IVault(payable(vaults[i])).strategy()));
            } else {
                console.log("Error: strategy is not upgraded", IVault(payable(vaults[i])).strategy().strategyLogicId());
            }
        }
    }

    function _upgradeSiloStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new SiloStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeSiloFarmStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new SiloFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO_FARM,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeSiloManagedFarmStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new SiloManagedFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO_MANAGED_FARM,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeIchiSwapxFarmStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new IchiSwapXFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.ICHI_SWAPX_FARM,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }
    //endregion ------------------------------------ Upgrade CVaults and strategies

    /*function _upgradePlatform() internal {
        address[] memory proxies = new address[](1);
        proxies[0] = PLATFORM;
        address[] memory implementations = new address[](1);
        implementations[0] = address(new Platform());
        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.05.1-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
        vm.stopPrank();
    }*/

    /*function _deployMetaVaultFactory() internal {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new MetaVaultFactory()));
        metaVaultFactory = IMetaVaultFactory(address(proxy));
        metaVaultFactory.initialize(PLATFORM);
    }*/

    function _setupMetaVaultFactory() internal {
        vm.prank(multisig);
        Platform(PLATFORM).setupMetaVaultFactory(address(metaVaultFactory));
    }

    function _setupImplementations() internal {
        address metaVaultImplementation = address(new MetaVault());
        address wrappedMetaVaultImplementation = address(new WrappedMetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(metaVaultImplementation);
        vm.prank(multisig);
        metaVaultFactory.setWrappedMetaVaultImplementation(wrappedMetaVaultImplementation);
    }

    function _deployMetaVaultByMetaVaultFactory(
        string memory type_,
        address pegAsset,
        string memory name_,
        string memory symbol_,
        address[] memory vaults_,
        uint[] memory proportions_
    ) internal returns (address metaVaultProxy) {
        vm.prank(multisig);
        return metaVaultFactory.deployMetaVault(
            bytes32(abi.encodePacked(name_)), type_, pegAsset, name_, symbol_, vaults_, proportions_
        );
    }

    function _deployWrapper(address metaVault) internal returns (address wrapper) {
        vm.prank(multisig);
        return metaVaultFactory.deployWrapper(bytes32(uint(uint160(metaVault))), metaVault);
    }

    /*function _deployMetaVaultStandalone(
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
    }*/

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
