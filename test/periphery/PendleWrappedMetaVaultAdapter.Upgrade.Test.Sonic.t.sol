// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {PendleERC4626WithAdapterSY} from "../../src/integrations/pendle/PendleERC4626WithAdapterSYFlatten.sol";
import {PendleWrappedMetaVaultAdapter} from "../../src/periphery/PendleWrappedMetaVaultAdapter.sol";
import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {IPendleCommonPoolDeployHelperV2} from "../../src/integrations/pendle/IPendleCommonPoolDeployHelperV2.sol";
import {console} from "forge-std/Test.sol";

contract PendleWrappedMetaVaultAdapterUpgradeTest is SonicSetup {
    address internal multisig;

    struct PoolConfigDecoded {
        address pt;
        uint256 scalarRoot;
        address sy;
        uint256 someParam;
        uint32 expiry;
        string name;
        string symbol;
    }

    constructor() {
        vm.rollFork(46122872); // Sep-08-2025 07:04:11 AM +UTC
    }

    //region ---------------------------------------- Tests using real SY
    function testDecodeData() public {
        bytes memory raw = hex"2becf31e00000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000180000000000000000000000000000000000000000000000000000000006943440000000000000000000000000000000000000000000000000000b1a2bc2ec5000000000000000000000000000000000000000000000000000003311fc80a57000000000000000000000000000000000000000000000000000001aa535d3d0c00000000000000000000000000000000000000000000000000000020af59ebef00000000000000000000000000001111111199558661bf7ff27b4f1623dc6b91aa3e00000000000000000000000000000000000000000000006c6b935b8bbd4000000000000000000000000000002ad631f72fb16d91c4953a7f4260a97c2fe2f31e0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000aaaaaaaac311d0572bffb4772fe985a750e8880500000000000000000000000000000000000000000000000000000000000000e4077f224a000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000174f8d9d8a9b25d14142bb0cb9d040060a1cf75c0000000000000000000000000000000000000000000000000000000000000018535920577261707065642053746162696c697479205553440000000000000000000000000000000000000000000000000000000000000000000000000000000b53592d776d65746155534400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory args = new bytes(raw.length - 4);
        for (uint256 i = 0; i < args.length; i++) {
            args[i] = raw[i + 4];
        }

        (
            bytes memory constructorParams,
            bytes memory initData,
            IPendleCommonPoolDeployHelperV2.PoolConfig memory config,
            address tokenToSeedLiquidity,
            uint256 amountToSeed,
            address syOwner
        ) = abi.decode(
            args,
            (bytes, bytes, IPendleCommonPoolDeployHelperV2.PoolConfig, address, uint256, address)
        );

        console.logBytes(constructorParams);
        console.logBytes(initData);
        console.log(tokenToSeedLiquidity);
        console.log(amountToSeed);
        console.log(syOwner);
        console.log("expiry", config.expiry);
        console.log("rateMin", config.rateMin);
        console.log("rateMax", config.rateMax);
        console.log("desiredImpliedRate", config.desiredImpliedRate);
        console.log("fee", config.fee);

//    0x000000000000000000000000aaaaaaaac311d0572bffb4772fe985a750e88805
//    0x077f224a000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000174f8d9d8a9b25d14142bb0cb9d040060a1cf75c0000000000000000000000000000000000000000000000000000000000000018535920577261707065642053746162696c697479205553440000000000000000000000000000000000000000000000000000000000000000000000000000000b53592d776d657461555344000000000000000000000000000000000000000000
//    0x1111111199558661Bf7Ff27b4F1623dC6b91Aa3e
//    2000000000000000000000
//    0x2aD631F72fB16d91c4953A7f4260A97C2fE2f31e
//    expiry 1766016000
//    rateMin 50000000000000000
//    rateMax 230000000000000000
//    desiredImpliedRate 120000000000000000
//    fee 9200000000000000
    }

    function testDeploy() public {
        IPendleCommonPoolDeployHelperV2 deployer = IPendleCommonPoolDeployHelperV2(
            SonicConstantsLib.PENDLE_COMMON_POOL_DEPLOY_HELPER_V2
        );

        vm.prank(0x2aD631F72fB16d91c4953A7f4260A97C2fE2f31e);
        deployer.deployERC20WithAdapterMarket(
            hex"000000000000000000000000aaaaaaaac311d0572bffb4772fe985a750e88805",
            hex"077f224a000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000174f8d9d8a9b25d14142bb0cb9d040060a1cf75c0000000000000000000000000000000000000000000000000000000000000018535920577261707065642053746162696c697479205553440000000000000000000000000000000000000000000000000000000000000000000000000000000b53592d776d657461555344000000000000000000000000000000000000000000",
            IPendleCommonPoolDeployHelperV2.PoolConfig({
                expiry: 1766016000,
                rateMin: 50000000000000000,
                rateMax: 230000000000000000,
                desiredImpliedRate: 120000000000000000,
                fee: 9200000000000000
            }),
            SonicConstantsLib.METAVAULT_metaUSD,
            2000000000000000000000,
            0x2aD631F72fB16d91c4953A7f4260A97C2fE2f31e // pendle deployer
        );


    }

    //endregion ---------------------------------------- Tests using real SY

    //region ---------------------------------------- Internal logic
    function _tryToDepositDirectly(IMetaVault metaVault, uint amount, bool shouldRevert) internal {
        uint snapshot = vm.snapshotState();

        _dealAndApproveSingle(address(this), address(metaVault), SonicConstantsLib.TOKEN_USDC, amount);
        address[] memory assets = metaVault.assetsForDeposit();
        uint[] memory amountsMax = new uint[](1);
        amountsMax[0] = amount;

        if (shouldRevert) {
            vm.expectRevert();
        }
        metaVault.depositAssets(assets, amountsMax, 0, address(this));

        vm.revertToState(snapshot);
    }

    function _tryToDepositToSY(
        address user,
        PendleERC4626WithAdapterSY sy_,
        address asset_,
        uint amount,
        bool shouldRevert
    ) internal {
        uint snapshot = vm.snapshotState();

        _dealAndApproveSingle(user, address(sy_), asset_, amount);
        uint shares = sy_.previewDeposit(asset_, amount);

        vm.prank(user);
        if (shouldRevert) {
            vm.expectRevert(IStabilityVault.WaitAFewBlocks.selector);
        }
        sy_.deposit(user, asset_, amount, shares * 999 / 1000);

        vm.revertToState(snapshot);
    }

    function _tryToRedeemFromSY(
        PendleERC4626WithAdapterSY sy_,
        address asset_,
        uint expectedAmount,
        bool shouldRevert
    ) internal {
        uint snapshot = vm.snapshotState();

        uint balance = sy_.balanceOf(address(this));

        if (shouldRevert) {
            vm.expectRevert(IStabilityVault.WaitAFewBlocks.selector);
        }
        sy_.redeem(address(this), balance, asset_, expectedAmount * 99 / 100, false);

        vm.revertToState(snapshot);
    }

    //endregion ---------------------------------------- Internal logic

    //region ---------------------------------------- Helpers
    function _dealAndApproveSingle(address user, address spender, address asset, uint amount) internal {
        deal(asset, user, amount);

        vm.prank(user);
        IERC20(asset).approve(spender, amount);
    }

    function _upgradeMetaVault(address metaVault_) internal {
        IMetaVaultFactory metaVaultFactory = IMetaVaultFactory(IPlatform(SonicConstantsLib.PLATFORM).metaVaultFactory());

        // Upgrade MetaVault to the new implementation
        address vaultImplementation = address(new MetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);
        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault_);
        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);
    }
    //endregion ---------------------------------------- Helpers
}
