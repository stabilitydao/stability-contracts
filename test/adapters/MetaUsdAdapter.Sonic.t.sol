// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MetaUsdAdapter} from "../../src/adapters/MetaUsdAdapter.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SonicSetup, SonicConstantsLib, IERC20} from "../base/chains/SonicSetup.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IMetaUsdAmmAdapter} from "../../src/interfaces/IMetaUsdAmmAdapter.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {console} from "forge-std/Test.sol";

contract MetaUsdAdapterTest is SonicSetup {
  address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

  bytes32 public _hash;
  MetaUsdAdapter public adapter;
  address public multisig;
  IMetaVault internal metaVault;

  constructor() {
    vm.rollFork(35998179); // Jun-26-2025 11:16:51 AM +UTC
    _init();
    _hash = keccak256(bytes(AmmAdapterIdLib.META_USD));
    metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSD);

    _addAdapter();
  }

  function testSwaps() public {
    uint got;
    address[] memory vaults = metaVault.vaults();
    assertEq(vaults.length, 2);

    for (uint i; i < 2; ++i) {
      if (i == 0) {
        _setZeroProportions(1, 0);
      } else {
        _setZeroProportions(0, 1);
      }

      deal(SonicConstantsLib.TOKEN_USDC, address(adapter), 100e6);
      _depositToMetaVault(100e6);
      uint metaVaultBalance = metaVault.balanceOf(address(this));

      got = _swap(
        SonicConstantsLib.METAVAULT_metaUSD,
        SonicConstantsLib.METAVAULT_metaUSD,
        SonicConstantsLib.TOKEN_USDC
      );
      vm.roll(block.number + 6);
      assertGt(got, 100e6);

      got = _swap(
        SonicConstantsLib.METAVAULT_metaUSD,
        SonicConstantsLib.TOKEN_USDC,
        SonicConstantsLib.METAVAULT_metaUSD
      );
      vm.roll(block.number + 6);
      assertGt(got, metaVaultBalance);
    }
  }

  //region ------------------------------------ Tests for view functions
  function testAmmAdapterId() public view {
    assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash);
  }

  function testPoolTokens() public view {
    address pool = SonicConstantsLib.METAVAULT_metaUSD;
    address[] memory poolTokens = adapter.poolTokens(pool);
    assertEq(poolTokens.length, 3);
    assertEq(poolTokens[0], pool);
    assertEq(poolTokens[1], IMetaVault(metaVault.vaults()[0]).assets()[0]);
    assertEq(poolTokens[2], IMetaVault(metaVault.vaults()[1]).assets()[0]);
  }

  function testNotSupportedMethods() public {
    vm.expectRevert("Not supported");
    adapter.getLiquidityForAmounts(address(0), new uint[](2));

    vm.expectRevert("Not supported");
    adapter.getProportions(address(0));
  }

  function testIERC165() public view {
    assertEq(adapter.supportsInterface(type(IMetaUsdAmmAdapter).interfaceId), true);
    assertEq(adapter.supportsInterface(type(IAmmAdapter).interfaceId), true);
    assertEq(adapter.supportsInterface(type(IERC165).interfaceId), true);
  }

  function testGetPriceDirect() public {
    address pool = SonicConstantsLib.METAVAULT_metaUSD;
    uint price;

    (uint assetPrice,) = IMetaVault(SonicConstantsLib.METAVAULT_metaUSDC).price();
    uint expectedPrice = 1e6 * 1e18 / assetPrice;
    price = adapter.getPrice(
      pool,
      SonicConstantsLib.METAVAULT_metaUSD,
      SonicConstantsLib.TOKEN_USDC,
      1e18
    );
    console.log("price", price);
    console.log("expectedPrice", expectedPrice);
    assertGt(price, expectedPrice);

    (assetPrice,) = IMetaVault(SonicConstantsLib.METAVAULT_metascUSD).price();
    expectedPrice = 1e6 * 1e18 / assetPrice;
    price = adapter.getPrice(
      pool,
      SonicConstantsLib.METAVAULT_metaUSD,
      SonicConstantsLib.TOKEN_scUSD,
      1e18
    );
    assertLt(price, 1034534);

    vm.expectRevert();
    adapter.getPrice(
      pool,
      SonicConstantsLib.METAVAULT_metaUSD,
      SonicConstantsLib.TOKEN_aUSDC,
      1e6
    );
  }

  function testGetPriceReverse() public {
    address pool = SonicConstantsLib.METAVAULT_metaUSD;
    (uint expectedPrice, ) = IMetaVault(SonicConstantsLib.METAVAULT_metaUSDC).price();
    uint price = adapter.getPrice(
      pool,
      SonicConstantsLib.TOKEN_USDC,
      SonicConstantsLib.METAVAULT_metaUSD,
      1e6
    );
    assertGt(price, expectedPrice);

    (expectedPrice, ) = IMetaVault(SonicConstantsLib.METAVAULT_metascUSD).price();
    price = adapter.getPrice(
      pool,
      SonicConstantsLib.TOKEN_scUSD,
      SonicConstantsLib.METAVAULT_metaUSD,
      1e6
    );
    assertLt(price, expectedPrice);

    vm.expectRevert();
    adapter.getPrice(
      pool,
      SonicConstantsLib.TOKEN_aUSDC,
      SonicConstantsLib.METAVAULT_metaUSD,
      1e6
    );
  }

  function testIMetaUsdAmmAdapter() public view {
    assertEq(
      adapter.assetForDeposit(SonicConstantsLib.METAVAULT_metaUSD),
      metaVault.assetsForDeposit()[0]
    );

    assertEq(
      adapter.assetForWithdraw(SonicConstantsLib.METAVAULT_metaUSD),
      metaVault.assetsForWithdraw()[0]
    );
  }
  //endregion ------------------------------------ Tests for view functions

  //region ------------------------------------ Internal logic
  function _swap(address pool, address tokenIn, address tokenOut /*, uint amount*/ ) internal returns (uint) {
    //deal(tokenIn, address(adapter), amount);
    uint balanceWas = IERC20(tokenOut).balanceOf(address(this));
    adapter.swap(pool, tokenIn, tokenOut, address(this), 1_000);
    return IERC20(tokenOut).balanceOf(address(this)) - balanceWas;
  }
  //endregion ------------------------------------ Internal logic

  //region ------------------------------------ Helper functions
  function _depositToMetaVault(uint amount) internal {
    address[] memory assets = metaVault.assetsForDeposit();
    uint[] memory amountsMax = new uint[](1);
    amountsMax[0] = amount;

    _dealAndApprove(address(this), address(metaVault), assets, amountsMax);

    (, uint sharesOut,) = metaVault.previewDepositAssets(assets, amountsMax);
    metaVault.depositAssets(assets, amountsMax, sharesOut, address(this));

    vm.roll(block.number + 6);
  }

  function _addAdapter() internal {
    Proxy proxy = new Proxy();
    proxy.initProxy(address(new MetaUsdAdapter()));
    MetaUsdAdapter(address(proxy)).init(PLATFORM);
    IPriceReader priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
    multisig = IPlatform(PLATFORM).multisig();

    vm.prank(multisig);
    priceReader.addAdapter(address(proxy));

    adapter = MetaUsdAdapter(address(proxy));
  }

  function _dealAndApprove(
    address user,
    address spender,
    address[] memory assets,
    uint[] memory amounts
  ) internal {
    for (uint j; j < assets.length; ++j) {
      deal(assets[j], user, amounts[j]);
      vm.prank(user);
      IERC20(assets[j]).approve(spender, amounts[j]);
    }
  }

  function _setZeroProportions(uint fromIndex, uint toIndex) internal {
    uint[] memory props = metaVault.targetProportions();
    props[toIndex] += props[fromIndex] - 2e16; //2e16 - allow to withdraw
    props[fromIndex] = 2e16;

    vm.prank(multisig);
    metaVault.setTargetProportions(props);
  }
  //endregion ------------------------------------ Helper functions
}
