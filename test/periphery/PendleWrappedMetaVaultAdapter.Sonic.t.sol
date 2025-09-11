// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPendleCommonPoolDeployHelperV2} from "../../src/integrations/pendle/IPendleCommonPoolDeployHelperV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {PendleERC4626WithAdapterSY} from "../../src/integrations/pendle/PendleERC4626WithAdapterSYFlatten.sol";
import {PendleWrappedMetaVaultAdapter} from "../../src/periphery/PendleWrappedMetaVaultAdapter.sol";
import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {console} from "forge-std/Test.sol";

contract PendleWrappedMetaVaultAdapterTest is SonicSetup {
    /// @notice a block with metaS workable
    uint internal constant FORK_BLOCK_META_S = 38601318; // Jul-15-2025 12:18:16 PM +UTC
    uint internal constant FORK_BLOCK = 45880691; // Sep-05-2025 06:47:56 PM +UTC

    constructor() {
        // fork is initialized inside tests
    }

    //region ---------------------------------------- Tests use real deploy
    function testForMetaUsd100Real() public {
        vm.rollFork(FORK_BLOCK);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSD);

        _getMetaUsdOnBalance(address(this), 2000e18, true);

        (PendleERC4626WithAdapterSY syMetaUsd, PendleWrappedMetaVaultAdapter adapter) =
            _realDeploy(SonicConstantsLib.METAVAULT_metaUSD, SonicConstantsLib.WRAPPED_METAVAULT_metaUSD, 2000e18);

        _testForMetaUsd(100e6, syMetaUsd, adapter, 2000e18);
    }
    //endregion ---------------------------------------- Tests use real deploy

    //region ---------------------------------------- Tests use flatten SY
    function testForMetaUsd100() public {
        vm.rollFork(FORK_BLOCK);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSD);

        (PendleERC4626WithAdapterSY syMetaUsd, PendleWrappedMetaVaultAdapter adapter) =
            _setUp(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD, SonicConstantsLib.METAVAULT_metaUSD);

        _testForMetaUsd(100e6, syMetaUsd, adapter, 0);
    }

    function testForMetaUsd1e6() public {
        vm.rollFork(FORK_BLOCK); // Jul-15-2025 12:18:16 PM +UTC
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSD);

        (PendleERC4626WithAdapterSY syMetaUsd, PendleWrappedMetaVaultAdapter adapter) =
            _setUp(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD, SonicConstantsLib.METAVAULT_metaUSD);

        _testForMetaUsd(1_000_000e6, syMetaUsd, adapter, 0);
    }

    function testForMetaS100() public {
        vm.rollFork(FORK_BLOCK_META_S);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaS);

        _testForMetaS(100e18);
    }

    function testForMetaS1e6() public {
        vm.rollFork(FORK_BLOCK_META_S);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaS);

        _testForMetaS(1_000_000e18);
    }

    function _testForMetaS(uint amount) internal {
        // -------------------- setup SY, SY-adapter and MetaVault
        (PendleERC4626WithAdapterSY syMetaS, PendleWrappedMetaVaultAdapter adapter) =
            _setUp(SonicConstantsLib.WRAPPED_METAVAULT_metaS, SonicConstantsLib.METAVAULT_metaS);

        // -------------------- deposit to SY
        _dealAndApproveSingle(address(this), address(syMetaS), SonicConstantsLib.TOKEN_wS, amount);
        {
            uint shares = syMetaS.previewDeposit(SonicConstantsLib.TOKEN_wS, amount);
            uint amountSharesOut =
                syMetaS.deposit(address(this), SonicConstantsLib.TOKEN_wS, amount, shares * 999 / 1000);

            assertEq(
                IERC20(SonicConstantsLib.TOKEN_wS).balanceOf(address(this)),
                0,
                "wS balance should be zero after deposit"
            );

            assertEq(syMetaS.balanceOf(address(this)), amountSharesOut, "SY balance should be expected");
        }

        // -------------------- user is not able to deposit / withdraw without waiting
        _tryToDepositToSY(address(this), syMetaS, SonicConstantsLib.TOKEN_wS, amount, true); // the user cannot deposit
        _tryToDepositToSY(address(2), syMetaS, SonicConstantsLib.TOKEN_wS, amount, true); // the other user cannot deposit too
        _tryToRedeemFromSY(syMetaS, SonicConstantsLib.TOKEN_wS, amount, true);

        // -------------------- wait a few blocks
        vm.roll(block.number + 6);

        // -------------------- withdraw half from SY
        uint balance = syMetaS.balanceOf(address(this));
        assertNotEq(balance, 0, "Balance should not be zero 1");

        syMetaS.redeem(address(this), balance / 2, SonicConstantsLib.TOKEN_wS, amount * 99 / 100 / 2, false);

        assertApproxEqAbs(
            IERC20(SonicConstantsLib.TOKEN_wS).balanceOf(address(this)),
            amount / 2,
            amount / 2 / 1000,
            "wS balance mismatch 1"
        );

        // -------------------- user IS ABLE to deposit without waiting
        // if we need to disable deposit after withdraw we need our own SY implementation or invent smth on wmetaUSD side
        _tryToDepositToSY(address(this), syMetaS, SonicConstantsLib.TOKEN_wS, amount, false);
        _tryToDepositToSY(address(2), syMetaS, SonicConstantsLib.TOKEN_wS, amount, false);

        // -------------------- user is not able to withdraw without waiting
        _tryToRedeemFromSY(syMetaS, SonicConstantsLib.TOKEN_wS, amount, true);

        // -------------------- wait a few blocks
        vm.roll(block.number + 6);

        // -------------------- withdraw all from SY
        balance = syMetaS.balanceOf(address(this));
        uint previewAmount = syMetaS.previewRedeem(SonicConstantsLib.TOKEN_wS, balance);
        assertNotEq(balance, 0, "Balance should not be zero 2");

        uint balanceAssetBeforeRedeem = IERC20(SonicConstantsLib.TOKEN_wS).balanceOf(address(this));
        uint redeemed = syMetaS.redeem(address(this), balance, SonicConstantsLib.TOKEN_wS, amount * 99 / 100 / 2, false);

        assertApproxEqAbs(
            IERC20(SonicConstantsLib.TOKEN_wS).balanceOf(address(this)), amount, amount / 1000, "wS balance mismatch 2"
        );

        assertEq(syMetaS.balanceOf(address(this)), 0, "Balance should be zero");
        assertApproxEqAbs(
            previewAmount, redeemed, previewAmount / 1e8, "Preview amount should be equal to redeemed amount 1"
        );
        assertApproxEqAbs(
            IERC20(SonicConstantsLib.TOKEN_wS).balanceOf(address(this)) - balanceAssetBeforeRedeem,
            previewAmount,
            previewAmount / 1e8,
            "User should withdraw expected previewed amount 1"
        );

        // -------------------- check zero balances
        assertEq(IERC20(SonicConstantsLib.TOKEN_wS).balanceOf(address(adapter)), 0, "Adapter wS balance should be zero");
        assertEq(
            IERC20(SonicConstantsLib.WRAPPED_METAVAULT_metaS).balanceOf(address(adapter)),
            0,
            "Adapter wmetaS balance should be zero"
        );
        assertApproxEqAbs(
            IERC20(SonicConstantsLib.METAVAULT_metaS).balanceOf(address(adapter)),
            0,
            1, // rounding issue on metaS side
            "Adapter metaS balance should be zero"
        );

        assertEq(IERC20(SonicConstantsLib.TOKEN_wS).balanceOf(address(syMetaS)), 0, "SY wS balance should be zero");
        assertEq(
            IERC20(SonicConstantsLib.WRAPPED_METAVAULT_metaS).balanceOf(address(syMetaS)),
            0,
            "SY wmetaS balance should be zero"
        );
        assertApproxEqAbs(
            IERC20(SonicConstantsLib.METAVAULT_metaS).balanceOf(address(syMetaS)),
            0,
            1, // rounding issue on metaS side
            "SY metaS balance should be zero"
        );
    }

    function testSalvage() public {
        vm.rollFork(FORK_BLOCK); // Jul-15-2025 12:18:16 PM +UTC
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSD);

        address receiver = makeAddr("receiver");
        (, PendleWrappedMetaVaultAdapter adapter) =
            _setUp(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD, SonicConstantsLib.METAVAULT_metaUSD);
        _dealAndApproveSingle(address(adapter), address(this), SonicConstantsLib.TOKEN_USDC, 100e6);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.NotOwner.selector);
        vm.prank(receiver);
        adapter.salvage(SonicConstantsLib.TOKEN_USDC, receiver, 100e6);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.ZeroAddress.selector);
        vm.prank(address(this));
        adapter.salvage(SonicConstantsLib.TOKEN_USDC, address(0), 100e6);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.ZeroAddress.selector);
        vm.prank(address(this));
        adapter.salvage(address(0), receiver, 100e6);

        vm.prank(address(this));
        adapter.salvage(SonicConstantsLib.TOKEN_USDC, receiver, 100e6);
    }

    function testBadPathNotWhitelistedSy() public {
        vm.rollFork(FORK_BLOCK); // Jul-15-2025 12:18:16 PM +UTC
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSD);

        address asset = SonicConstantsLib.TOKEN_USDC;
        uint amount = 100e6;

        // -------------------- setup SY, SY-adapter and MetaVault
        (PendleERC4626WithAdapterSY syMetaUsd, PendleWrappedMetaVaultAdapter adapter) =
            _setUp(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD, SonicConstantsLib.METAVAULT_metaUSD);
        _dealAndApproveSingle(address(this), address(syMetaUsd), asset, amount);

        // -------------------- deposit to SY
        vm.prank(address(this));
        adapter.changeWhitelist(address(syMetaUsd), false);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.NotWhitelisted.selector);
        syMetaUsd.deposit(address(this), asset, amount, 0);

        vm.prank(address(this));
        adapter.changeWhitelist(address(syMetaUsd), true);

        syMetaUsd.deposit(address(this), asset, amount, 0);
        vm.roll(block.number + 6);

        // -------------------- withdraw all from SY
        uint balance = syMetaUsd.balanceOf(address(this));

        vm.prank(address(this));
        adapter.changeWhitelist(address(syMetaUsd), false);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.NotWhitelisted.selector);
        syMetaUsd.redeem(address(this), balance, asset, 0, false);

        vm.prank(address(this));
        adapter.changeWhitelist(address(syMetaUsd), true);

        syMetaUsd.redeem(address(this), balance, asset, 0, false);
    }

    function testBadPathIncorrectTokens() public {
        vm.rollFork(FORK_BLOCK); // Jul-15-2025 12:18:16 PM +UTC
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSD);

        address asset = SonicConstantsLib.TOKEN_USDC;
        uint amount = 100e6;

        // -------------------- setup SY, SY-adapter and MetaVault
        (PendleERC4626WithAdapterSY syMetaUsd, PendleWrappedMetaVaultAdapter adapter) =
            _setUp(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD, SonicConstantsLib.METAVAULT_metaUSD);
        _dealAndApproveSingle(address(this), address(syMetaUsd), asset, amount);
        _dealAndApproveSingle(address(this), address(syMetaUsd), SonicConstantsLib.TOKEN_wS, amount);

        // -------------------- deposit to SY
        vm.expectRevert(PendleWrappedMetaVaultAdapter.IncorrectToken.selector);
        vm.prank(address(syMetaUsd));
        adapter.convertToDeposit(SonicConstantsLib.TOKEN_wS, amount);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.IncorrectToken.selector);
        adapter.previewConvertToRedeem(SonicConstantsLib.TOKEN_wS, amount);

        syMetaUsd.deposit(address(this), asset, amount, 0);
        vm.roll(block.number + 6);

        // -------------------- withdraw all from SY
        uint balance = syMetaUsd.balanceOf(address(this));

        vm.expectRevert(PendleWrappedMetaVaultAdapter.IncorrectToken.selector);
        vm.prank(address(syMetaUsd));
        adapter.convertToRedeem(SonicConstantsLib.TOKEN_wS, amount);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.IncorrectToken.selector);
        adapter.previewConvertToDeposit(SonicConstantsLib.TOKEN_wS, amount);

        syMetaUsd.redeem(address(this), balance, asset, 0, false);
    }

    function testBadPathsChangeWhitelist() public {
        vm.rollFork(FORK_BLOCK); // Jul-15-2025 12:18:16 PM +UTC
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSD);

        (PendleERC4626WithAdapterSY syMetaUsd, PendleWrappedMetaVaultAdapter adapter) =
            _setUp(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD, SonicConstantsLib.METAVAULT_metaUSD);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.NotOwner.selector);
        vm.prank(address(314));
        adapter.changeWhitelist(address(syMetaUsd), true);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.ZeroAddress.selector);
        vm.prank(address(this));
        adapter.changeWhitelist(address(0), false);

        vm.prank(address(this));
        adapter.changeWhitelist(address(syMetaUsd), true);
        assertEq(adapter.whitelisted(address(syMetaUsd)), true);

        address newOwner = makeAddr("newOwner");

        vm.expectRevert(PendleWrappedMetaVaultAdapter.NotOwner.selector);
        vm.prank(newOwner);
        adapter.changeOwner(newOwner);

        assertEq(adapter.owner(), address(this));
        vm.prank(address(this));
        adapter.changeOwner(newOwner);
        assertEq(adapter.owner(), newOwner);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.NotOwner.selector);
        vm.prank(address(this));
        adapter.changeWhitelist(address(syMetaUsd), false);

        vm.prank(newOwner);
        adapter.changeWhitelist(address(syMetaUsd), false);

        assertEq(adapter.whitelisted(address(syMetaUsd)), false);
    }

    function testBadPathsConstructor() public {
        vm.rollFork(FORK_BLOCK); // Jul-15-2025 12:18:16 PM +UTC
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSD);

        vm.expectRevert(PendleWrappedMetaVaultAdapter.ZeroAddress.selector);
        new PendleWrappedMetaVaultAdapter(address(0));
    }
    //endregion ---------------------------------------- Tests use flatten SY

    //region ---------------------------------------- Internal logic
    function _realDeploy(
        address metaVault_,
        address wrappedMetaVault_,
        uint initialWMetaUsdAmount_
    ) internal returns (PendleERC4626WithAdapterSY syMetaUsd, PendleWrappedMetaVaultAdapter pendleAdapter) {
        address multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();

        pendleAdapter = new PendleWrappedMetaVaultAdapter(metaVault_);

        bytes memory initParams = abi.encodeWithSelector(
            bytes4(keccak256("initialize(string,string,address)")),
            "SY Wrapped Stability USD",
            "SY-wmetaUSD",
            address(pendleAdapter)
        );

        IPendleCommonPoolDeployHelperV2 _deployerHelper =
            IPendleCommonPoolDeployHelperV2(SonicConstantsLib.PENDLE_COMMON_POOL_DEPLOY_HELPER_V2);

        bytes memory constructorParams = abi.encode(wrappedMetaVault_);

        // ------------------------- Whitelist before deploy
        //        vm.prank(multisig); // todo
        //        IMetaVault(metaVault_).changeWhitelist(address(_deployerHelper), true);

        // Temporarily whitelist PoolDeployHelper
        //        vm.prank(address(this)); // todo
        //        pendleAdapter.changeWhitelist(address(_deployerHelper), true);

        // Whitelist Pendle router
        //        vm.prank(address(this)); // todo
        //        pendleAdapter.changeWhitelist(SonicConstantsLib.PENDLE_ROUTER, true);

        //        vm.prank(multisig); // todo
        //        IMetaVault(metaVault_).changeWhitelist(SonicConstantsLib.PENDLE_ROUTER, true);

        vm.roll(block.number + 6);

        // ------------------------- Deploy
        IPendleCommonPoolDeployHelperV2.PoolConfig memory config = IPendleCommonPoolDeployHelperV2.PoolConfig({
            expiry: 1766016000,
            rateMin: 50000000000000000,
            rateMax: 230000000000000000,
            desiredImpliedRate: 120000000000000000,
            fee: 9200000000000000
        });

        vm.prank(address(this));
        IERC20(wrappedMetaVault_).approve(address(_deployerHelper), initialWMetaUsdAmount_);

        //        vm.prank(address(this));
        //        IERC20(metaVault_).approve(address(_deployerHelper), initialWMetaUsdAmount_);

        vm.prank(address(this));
        IPendleCommonPoolDeployHelperV2.PoolDeploymentAddrs memory pda = _deployerHelper.deployERC4626WithAdapterMarket(
            constructorParams,
            initParams,
            config,
            wrappedMetaVault_, // 0x1111111199558661Bf7Ff27b4F1623dC6b91Aa3e
            initialWMetaUsdAmount_, // 2000000000000000000000
            address(this)
        );

        // ------------------------- Whitelist after deploy
        syMetaUsd = PendleERC4626WithAdapterSY(payable(pda.SY));

        vm.prank(address(this));
        pendleAdapter.changeWhitelist(address(syMetaUsd), true);

        vm.prank(multisig);
        IMetaVault(metaVault_).changeWhitelist(address(pendleAdapter), true);

        return (syMetaUsd, pendleAdapter);
    }

    function _testForMetaUsd(
        uint amount,
        PendleERC4626WithAdapterSY syMetaUsd,
        PendleWrappedMetaVaultAdapter adapter,
        uint initialAmount
    ) internal {
        // -------------------- deposit to SY
        _dealAndApproveSingle(address(this), address(syMetaUsd), SonicConstantsLib.TOKEN_USDC, amount);
        {
            uint shares = syMetaUsd.previewDeposit(SonicConstantsLib.TOKEN_USDC, amount);
            uint amountSharesOut =
                syMetaUsd.deposit(address(this), SonicConstantsLib.TOKEN_USDC, amount, shares * 999 / 1000);

            assertEq(
                IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this)),
                0,
                "USDC balance should be zero after deposit"
            );

            assertEq(syMetaUsd.balanceOf(address(this)), amountSharesOut, "SY balance should be expected");
        }

        // -------------------- user is not able to deposit / withdraw without waiting
        _tryToDepositToSY(address(this), syMetaUsd, SonicConstantsLib.TOKEN_USDC, amount, true); // the user cannot deposit
        _tryToDepositToSY(address(2), syMetaUsd, SonicConstantsLib.TOKEN_USDC, amount, true); // the other user cannot deposit too
        _tryToRedeemFromSY(syMetaUsd, SonicConstantsLib.TOKEN_USDC, amount, true);

        // -------------------- wait a few blocks
        vm.roll(block.number + 6);

        // -------------------- withdraw half from SY
        uint balance = syMetaUsd.balanceOf(address(this));
        assertNotEq(balance, 0, "Balance should not be zero 1");

        syMetaUsd.redeem(address(this), balance / 2, SonicConstantsLib.TOKEN_USDC, amount * 99 / 100 / 2, false);

        assertApproxEqAbs(
            IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this)),
            amount / 2,
            amount / 2 / 1000,
            "USDC balance mismatch 1"
        );

        // -------------------- user IS ABLE to deposit without waiting
        // if we need to disable deposit after withdraw we need our own SY implementation or invent smth on wmetaUSD side
        _tryToDepositToSY(address(this), syMetaUsd, SonicConstantsLib.TOKEN_USDC, amount, false);
        _tryToDepositToSY(address(2), syMetaUsd, SonicConstantsLib.TOKEN_USDC, amount, false);

        // -------------------- user is not able to withdraw without waiting
        _tryToRedeemFromSY(syMetaUsd, SonicConstantsLib.TOKEN_USDC, amount, true);

        // -------------------- wait a few blocks
        vm.roll(block.number + 6);

        // -------------------- withdraw all from SY
        balance = syMetaUsd.balanceOf(address(this));
        uint previewAmount = syMetaUsd.previewRedeem(SonicConstantsLib.TOKEN_USDC, balance);
        assertNotEq(balance, 0, "Balance should not be zero 2");

        uint balanceUsdcBeforeRedeem = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this));
        uint redeemed =
            syMetaUsd.redeem(address(this), balance, SonicConstantsLib.TOKEN_USDC, amount * 99 / 100 / 2, false);

        assertApproxEqAbs(
            IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this)),
            amount,
            amount / 1000,
            "USDC balance mismatch 2"
        );

        assertEq(syMetaUsd.balanceOf(address(this)), 0, "Balance should be zero");
        assertApproxEqAbs(previewAmount, redeemed, 1, "Preview amount should be equal to redeemed amount");
        assertApproxEqAbs(
            IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this)) - balanceUsdcBeforeRedeem,
            previewAmount,
            1,
            "User should withdraw expected previewed amount"
        );

        // -------------------- check zero balances
        assertEq(
            IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(adapter)), 0, "Adapter USDC balance should be zero"
        );
        assertEq(
            IERC20(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD).balanceOf(address(adapter)),
            0,
            "Adapter wmetaUSD balance should be zero"
        );
        assertApproxEqAbs(
            IERC20(SonicConstantsLib.METAVAULT_metaUSD).balanceOf(address(adapter)),
            0,
            1, // rounding issue on metaUsd side
            "Adapter metaUSD balance should be zero"
        );

        assertEq(
            IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(syMetaUsd)), 0, "SY USDC balance should be zero"
        );
        assertEq(
            IERC20(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD).balanceOf(address(syMetaUsd)),
            initialAmount,
            "SY wmetaUSD balance should be zero"
        );
        assertApproxEqAbs(
            IERC20(SonicConstantsLib.METAVAULT_metaUSD).balanceOf(address(syMetaUsd)),
            0,
            1, // rounding issue on metaUsd side
            "SY metaUSD balance should be zero"
        );
    }

    function _setUp(
        address wrappedMetaVault_,
        address metaVault_
    ) internal returns (PendleERC4626WithAdapterSY syMetaUsd, PendleWrappedMetaVaultAdapter adapter) {
        address multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();

        adapter = new PendleWrappedMetaVaultAdapter(metaVault_);
        syMetaUsd = new PendleERC4626WithAdapterSY(wrappedMetaVault_, address(adapter));

        vm.prank(multisig);
        IMetaVault(metaVault_).changeWhitelist(address(adapter), true);

        vm.prank(address(this));
        adapter.changeWhitelist(address(syMetaUsd), true);

        {
            address owner = syMetaUsd.owner();
            vm.prank(owner);
            syMetaUsd.setAdapter(address(adapter));
        }
    }

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
        address multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();
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

    function _getMetaUsdOnBalance(address user, uint amountMetaVaultTokens, bool wrap) internal {
        IMetaVault metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSD);

        // we don't know exact amount of USDC required to receive exact amountMetaVaultTokens
        // so we deposit a bit large amount of USDC
        address[] memory _assets = metaVault.assetsForDeposit();
        uint[] memory amountsMax = new uint[](1);
        amountsMax[0] = 2 * amountMetaVaultTokens / 1e12;

        deal(SonicConstantsLib.TOKEN_USDC, user, amountsMax[0]);

        vm.startPrank(user);
        IERC20(SonicConstantsLib.TOKEN_USDC).approve(
            address(metaVault), IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(user)
        );
        metaVault.depositAssets(_assets, amountsMax, 0, user);
        vm.roll(block.number + 6);
        vm.stopPrank();

        if (wrap) {
            vm.startPrank(user);
            IWrappedMetaVault wrappedMetaVault = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD);
            metaVault.approve(address(wrappedMetaVault), metaVault.balanceOf(user));
            wrappedMetaVault.deposit(metaVault.balanceOf(user), user, 0);
            vm.stopPrank();

            vm.roll(block.number + 6);
        }
    }
    //endregion ---------------------------------------- Helpers
}
