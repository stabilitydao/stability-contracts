// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {PendleERC4626WithAdapterSY} from "../../src/integrations/pendle/PendleERC4626WithAdapterSYFlatten.sol";
import {PendleWrappedMetaVaultAdapter} from "../../src/adapters/PendleWrappedMetaVaultAdapter.sol";
import {SonicSetup, SonicConstantsLib, IERC20} from "../base/chains/SonicSetup.sol";
import {console} from "forge-std/Test.sol";

contract PendleWrappedMetaVaultAdapterTest is SonicSetup {
  address internal multisig;
  PendleERC4626WithAdapterSY internal syMetaUsd;
  PendleERC4626WithAdapterSY internal syMetaS;

  constructor() {
    vm.rollFork(38601318); // Jul-15-2025 12:18:16 PM +UTC
    multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();
    _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSD);
  }

  function testDepositToMetaUsd() public {
    console.log("this", address(this));
    // -------------------- setup SY, SY-adapter and MetaVault
    PendleWrappedMetaVaultAdapter adapter = new PendleWrappedMetaVaultAdapter(SonicConstantsLib.METAVAULT_metaUSD);
    syMetaUsd = new PendleERC4626WithAdapterSY(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD, address(adapter));

    vm.prank(multisig);
    IMetaVault(SonicConstantsLib.METAVAULT_metaUSD).changeWhitelist(address(adapter), true);

    vm.prank(address(this));
    adapter.changeWhitelist(address(syMetaUsd), true);

    {
      address owner = syMetaUsd.owner();
      vm.prank(owner);
      syMetaUsd.setAdapter(address(adapter));
    }

    // -------------------- deposit to SY
    uint amount = 100e6;
    _dealAndApproveSingle(address(this), address(syMetaUsd), SonicConstantsLib.TOKEN_USDC, amount);
    uint shares = syMetaUsd.previewDeposit(SonicConstantsLib.TOKEN_USDC, amount);
    uint amountSharesOut = syMetaUsd.deposit(address(this), SonicConstantsLib.TOKEN_USDC, amount, shares * 999/1000);
    uint balance = syMetaUsd.balanceOf(address(this));

    assertEq(
      IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this)),
      0,
      "USDC balance should be zero after deposit"
    );
    assertNotEq(balance, 0, "Balance should not be zero");

    // -------------------- user is not able to deposit / withdraw directly to / from metavault
    _tryToDeposit(IMetaVault(SonicConstantsLib.METAVAULT_metaUSD), amount, true);

    // -------------------- roll
    vm.roll(block.number + 6);


    // -------------------- withdraw from SY
    syMetaUsd.redeem(
      address(this),
      balance,
      SonicConstantsLib.TOKEN_USDC,
      amount * 99/100,
      false
    );

    assertApproxEqAbs(
      IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(this)),
      amount,
      amount/1000,
      "USDC balance mismatch"
    );

    assertEq(syMetaUsd.balanceOf(address(this)), 0, "Balance should be zero");

  }

  //region ---------------------------------------- Internal logic
  function _tryToDeposit(IMetaVault metaVault, uint amount, bool shouldRevert) internal {
    uint snapshot = vm.snapshotState();

    _dealAndApproveSingle(address(this), address(metaVault), SonicConstantsLib.TOKEN_USDC, amount);
    address[] memory assets = metaVault.assetsForDeposit();
    uint[] memory amountsMax = new uint[](1);
    amountsMax[0] = amount;

    if (shouldRevert) {
      vm.expectRevert();
    }
    metaVault.depositAssets(assets, amountsMax, 0, address(this));

    vm.revertTo(snapshot);
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