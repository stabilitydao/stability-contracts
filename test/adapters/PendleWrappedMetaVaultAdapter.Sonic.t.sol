// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PendleWrappedMetaVaultAdapter} from "../../src/adapters/PendleWrappedMetaVaultAdapter.sol";
import {PendleERC4626WithAdapterSY} from "../../src/integrations/pendle/PendleERC4626WithAdapterSYFlatten.sol";
import {SonicSetup, SonicConstantsLib, IERC20} from "../base/chains/SonicSetup.sol";
import {console} from "forge-std/Test.sol";

contract PendleWrappedMetaVaultAdapterTest is SonicSetup {
  PendleERC4626WithAdapterSY internal syMetaUsd;
  PendleERC4626WithAdapterSY internal syMetaS;

  constructor() {
    vm.rollFork(38601318); // Jul-15-2025 12:18:16 PM +UTC

//    syMetaS = new PendleERC4626WithAdapterSY(SonicConstantsLib.METAVAULT_metaS);
  }

  function testDepositToMetaUsd() public {
    PendleWrappedMetaVaultAdapter adapter = new PendleWrappedMetaVaultAdapter(SonicConstantsLib.METAVAULT_metaUSD);
    syMetaUsd = new PendleERC4626WithAdapterSY(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD, address(adapter));

    {
      address owner = syMetaUsd.owner();
      vm.prank(owner);
      syMetaUsd.setAdapter(address(adapter));
    }

    uint amount = 100e6;
    _dealAndApproveSingle(address(this), address(syMetaUsd), SonicConstantsLib.TOKEN_USDC, amount);
    uint shares = syMetaUsd.previewDeposit(SonicConstantsLib.TOKEN_USDC, amount);
    uint amountSharesOut = syMetaUsd.deposit(address(this), SonicConstantsLib.TOKEN_USDC, amount, shares * 999/1000);
  }

  //region ---------------------------------------- Helpers
  function _dealAndApproveSingle(address user, address spender, address asset, uint amount) internal {
    deal(asset, user, amount);

    vm.prank(user);
    IERC20(asset).approve(spender, amount);
  }

  //endregion ---------------------------------------- Helpers
}