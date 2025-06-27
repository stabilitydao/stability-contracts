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
      uint snapshot = vm.snapshot();
      address token = i == 0 ? SonicConstantsLib.TOKEN_USDC : SonicConstantsLib.TOKEN_scUSD;
      // set up vault for deposit
      if (i == 0) {
        _setProportions(i, true);
      } else {
        _setProportions(i, true);
      }
      assertEq(metaVault.vaultForDeposit(), vaults[i], "vaultForDeposit mismatch");

      // deposit 100 USDC to MetaVault and get MetaUSD on balance
      deal(token, address(this), 100e6);
      _depositToMetaVault(100e6, address(this));
      uint metaVaultBalance = metaVault.balanceOf(address(this));

      // set up vault for withdraw
      if (i == 0) {
        _setProportions(i, false);
      } else {
        _setProportions(i, false);
      }
      if (metaVault.vaultForWithdraw() != vaults[i]) {
        deal(token, address(1), 1_000_000e6);
        _depositToMetaVault(1_000_000e6, address(1));
      }
      assertEq(metaVault.vaultForWithdraw(), vaults[i], "vaultForWithdraw mismatch");

      // swap 100 MetaUSD to USDC
      got = _swap(
        SonicConstantsLib.METAVAULT_metaUSD,
        SonicConstantsLib.METAVAULT_metaUSD,
        token,
        metaVaultBalance,
        1_000 // 1% price impact
      );
      vm.roll(block.number + 6);
      assertApproxEqAbs(got, 100e6, 1, "got all tokens back (difference in 1 decimal is allowed)");

      // set up vault for deposit
      if (i == 0) {
        _setProportions(i, true);
      } else {
        _setProportions(i, true);
      }
      assertEq(metaVault.vaultForDeposit(), vaults[i], "vaultForDeposit mismatch 2");

      // swap 100 USDC to MetaUSD
      got = _swap(
        SonicConstantsLib.METAVAULT_metaUSD,
        token,
        SonicConstantsLib.METAVAULT_metaUSD,
        got,
        1_000 // 1% price impact
      );
      vm.roll(block.number + 6);
      assertLt(
        _getDiffPercent18(got, metaVaultBalance),
        1e10,
        "got ~ metaVaultBalance (losses are almost zero)"
      );

      vm.revertToState(snapshot);
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

    // 100 MetaUSD => USDC
    (uint assetPrice,) = IMetaVault(SonicConstantsLib.METAVAULT_metaUSDC).price();
    uint expectedPrice = 1e6 * assetPrice / 1e18;
    price = adapter.getPrice(
      pool,
      SonicConstantsLib.METAVAULT_metaUSD,
      SonicConstantsLib.TOKEN_USDC,
      100 * 1e18
    );
    assertEq(price, 100 * expectedPrice);

    // 0 MetaUSD == 1 MetaUSD => USDC
    price = adapter.getPrice(
      pool,
      SonicConstantsLib.METAVAULT_metaUSD,
      SonicConstantsLib.TOKEN_USDC,
      0
    );
    assertEq(price, expectedPrice);


    // 100 MetaUSD => scUSD
    (assetPrice,) = IMetaVault(SonicConstantsLib.METAVAULT_metascUSD).price();
    expectedPrice = 1e6 * assetPrice / 1e18;
    price = adapter.getPrice(
      pool,
      SonicConstantsLib.METAVAULT_metaUSD,
      SonicConstantsLib.TOKEN_scUSD,
      1e18
    );
    assertEq(price, expectedPrice);

    // 1 MetaUSD => aUSDC (not supported token)
    vm.expectRevert();
    adapter.getPrice(
      pool,
      SonicConstantsLib.METAVAULT_metaUSD,
      SonicConstantsLib.TOKEN_aUSDC,
      0
    );

    // 1 USDC => 1 scUSD (there is no MetaUSD)
    vm.expectRevert();
    adapter.getPrice(
      pool,
      SonicConstantsLib.TOKEN_USDC,
      SonicConstantsLib.TOKEN_scUSD,
      0
    );

  }

  function testGetPriceReverse() public {
    address pool = SonicConstantsLib.METAVAULT_metaUSD;

    // 100 USDC => MetaUSD
    (uint assertPrice, ) = IMetaVault(SonicConstantsLib.METAVAULT_metaUSDC).price();
    uint expectedPrice100 = 100 * 1e18 * 1e18 / assertPrice;
    uint price = adapter.getPrice(
      pool,
      SonicConstantsLib.TOKEN_USDC,
      SonicConstantsLib.METAVAULT_metaUSD,
      100e6
    );
    assertEq(price, expectedPrice100);

    // 100 scUSD => MetaUSD
    (assertPrice, ) = IMetaVault(SonicConstantsLib.METAVAULT_metascUSD).price();
    expectedPrice100 = 100 * 1e18 * 1e18 / assertPrice;
    price = adapter.getPrice(
      pool,
      SonicConstantsLib.TOKEN_scUSD,
      SonicConstantsLib.METAVAULT_metaUSD,
      100e6
    );
    assertEq(price, expectedPrice100);

    // 0 scUSD == 1 scUSD => MetaUSD
    price = adapter.getPrice(
      pool,
      SonicConstantsLib.TOKEN_scUSD,
      SonicConstantsLib.METAVAULT_metaUSD,
      0
    );
    assertEq(price, expectedPrice100 / 100);

    // 1 aUSDC (not supported token) => MetaUSD
    vm.expectRevert();
    adapter.getPrice(
      pool,
      SonicConstantsLib.TOKEN_aUSDC,
      SonicConstantsLib.METAVAULT_metaUSD,
      1e6
    );

    // 1 scUSD => 1 USDC (there is no MetaUSD)
    vm.expectRevert();
    adapter.getPrice(
      pool,
      SonicConstantsLib.TOKEN_scUSD,
      SonicConstantsLib.TOKEN_USDC,
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
  function _swap(address pool, address tokenIn, address tokenOut, uint amount, uint priceImpact) internal returns (uint) {
    IERC20(tokenIn).transfer(address(adapter), amount);
    vm.roll(block.number + 6);

    uint balanceWas = IERC20(tokenOut).balanceOf(address(this));
    adapter.swap(pool, tokenIn, tokenOut, address(this), priceImpact);
    return IERC20(tokenOut).balanceOf(address(this)) - balanceWas;
  }
  //endregion ------------------------------------ Internal logic

  //region ------------------------------------ Helper functions
  function _depositToMetaVault(uint amount, address user) internal {
    address[] memory assets = metaVault.assetsForDeposit();
    uint[] memory amountsMax = new uint[](1);
    amountsMax[0] = amount;

    _dealAndApprove(user, address(metaVault), assets, amountsMax);

    (, uint sharesOut,) = metaVault.previewDepositAssets(assets, amountsMax);

    vm.prank(user);
    metaVault.depositAssets(assets, amountsMax, sharesOut*99/100, user);

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

  function _setProportions(uint index, bool toDeposit) internal {
    uint indexOpposite = index == 0 ? 1 : 0;
    uint[] memory props = metaVault.targetProportions();
    uint[] memory current = metaVault.currentProportions();

    if (toDeposit) {
      props[index] = 1e18;
      props[indexOpposite] = 0;
    } else {
      props[index] = 1e18 - current[indexOpposite];
      props[indexOpposite] = current[indexOpposite];
    }

    vm.prank(multisig);
    metaVault.setTargetProportions(props);

//    props = metaVault.targetProportions();
//    for (uint i; i < current.length; ++i) {
//      console.log("current, target", i, current[i], props[i]);
//    }
  }

  function _getDiffPercent18(uint x, uint y) internal pure returns (uint) {
    return x > y ? (x - y) * 1e18 / x : (y - x) * 1e18 / x;
  }
  //endregion ------------------------------------ Helper functions
}
