// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MetaVaultAdapter} from "../../src/adapters/MetaVaultAdapter.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SonicSetup, SonicConstantsLib, IERC20} from "../base/chains/SonicSetup.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IMetaVaultAmmAdapter} from "../../src/interfaces/IMetaVaultAmmAdapter.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {console} from "forge-std/Test.sol";

contract MetaVaultAdapterTest is SonicSetup {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    bytes32 public _hash;
    MetaVaultAdapter public adapter;
    address public multisig;
    IMetaVault internal metaVault;

    constructor() {
        vm.rollFork(35998179); // Jun-26-2025 11:16:51 AM +UTC
        _init();
        _hash = keccak256(bytes(AmmAdapterIdLib.META_VAULT));
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
            assertLt(_getDiffPercent18(got, metaVaultBalance), 1e10, "got ~ metaVaultBalance (losses are almost zero)");

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
        assertEq(adapter.supportsInterface(type(IMetaVaultAmmAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IAmmAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IERC165).interfaceId), true);
    }

    function testGetPriceDirectBadPaths() public {
        address pool = SonicConstantsLib.METAVAULT_metaUSD;

        // 1 MetaUSD => aUSDC (not supported token)
        vm.expectRevert();
        adapter.getPrice(pool, SonicConstantsLib.METAVAULT_metaUSD, SonicConstantsLib.TOKEN_aUSDC, 0);

        // 1 USDC => 1 scUSD (there is no MetaUSD)
        vm.expectRevert();
        adapter.getPrice(pool, SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_scUSD, 0);
    }

    function testIMetaVaultAmmAdapter() public view {
        assertEq(adapter.assetForDeposit(SonicConstantsLib.METAVAULT_metaUSD), metaVault.assetsForDeposit()[0]);

        assertEq(adapter.assetForWithdraw(SonicConstantsLib.METAVAULT_metaUSD), metaVault.assetsForWithdraw()[0]);
    }
    //endregion ------------------------------------ Tests for view functions

    //region ------------------------------------ Get price MetaUSD in other tokens
    function testGetPriceDirectUSDC() public view {
        uint price;
        address pool = SonicConstantsLib.METAVAULT_metaUSD;

        // ---------------------- get amount of USDC that should be received for the given amount of MetaUSD
        // Example:
        //  1 MetaUSD = $1
        //  1 USDC = $0.99985
        //  1 MetaUSD = 1.000150 USDC

        // MetaUSD has 18 decimals, USDC has 6 decimals

        (uint usdcPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(SonicConstantsLib.TOKEN_USDC);

        // 100 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_metaUSD, SonicConstantsLib.TOKEN_USDC, 100 * 1e18);
        assertEq(price, 1e6 * 100 * 1e18 / usdcPrice, "100 MetaUSD => USDC");

        // 2 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_metaUSD, SonicConstantsLib.TOKEN_USDC, 2e18);
        assertEq(price, 1e6 * 2 * 1e18 / usdcPrice, "2 MetaUSD");

        // 0 MetaUSD == 1 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_metaUSD, SonicConstantsLib.TOKEN_USDC, 0);
        assertEq(price, 1e6 * 1 * 1e18 / usdcPrice, "0 MetaUSD");
    }

    function testGetPriceDirectWS() public view {
        uint price;
        address pool = SonicConstantsLib.METAVAULT_metaS;

        // ---------------------- get amount of wS that should be received for the given amount of MetaUSD

        // Example:
        // 1 MetaS = $0.3098776
        // 1 wS = $0.3098776
        // 1 MetaS = 1 wS

        // MetaS has 18 decimals, wS has 18 decimals

        // 100 MetaS => wS
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_metaS, SonicConstantsLib.TOKEN_wS, 100 * 1e18);
        assertEq(price, 100e18, "100 MetaS => wS");

        // 0 MetaUSD == 1 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_metaS, SonicConstantsLib.TOKEN_wS, 0);
        assertEq(price, 1e18, "0 wS");
    }

    function testGetPriceDirectScUSD() public view {
        uint price;
        address pool = SonicConstantsLib.METAVAULT_metaUSD;

        // ---------------------- get amount of scUSD that should be received for the given amount of MetaUSD
        // Example:
        //  1 MetaUSD = $1
        //  1 scUSD = $0.99911831
        //  1 MetaUSD = 1.000882 scUSD

        // MetaUSD has 18 decimals, scUSD has 6 decimals

        (uint scusdPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(SonicConstantsLib.TOKEN_scUSD);

        // 100 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_metaUSD, SonicConstantsLib.TOKEN_scUSD, 100 * 1e18);
        assertEq(price, 1e6 * 100 * 1e18 / scusdPrice, "100 MetaUSD => scUSD");

        // 2 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_metaUSD, SonicConstantsLib.TOKEN_scUSD, 2e18);
        assertEq(price, 1e6 * 2 * 1e18 / scusdPrice, "2 MetaUSD");

        // 0 MetaUSD == 1 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_metaUSD, SonicConstantsLib.TOKEN_scUSD, 0);
        assertEq(price, 1e6 * 1 * 1e18 / scusdPrice, "0 MetaUSD");
    }
    //endregion ------------------------------------ Get price MetaUSD in other tokens

    //region ------------------------------------ Get price other tokens in other MetaUSD
    function testGetPriceReverseUSDC() public view {
        uint price;
        address pool = SonicConstantsLib.METAVAULT_metaUSD;

        // ---------------------- get amount of MetaUSD that should be received for the given amount of USDC
        // Example:
        //  1 MetaUSD = $1
        //  1 USDC = $0.99985
        //  1 MetaUSD = 1.000150 USDC

        // MetaUSD has 18 decimals, USDC has 6 decimals

        (uint usdcPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(SonicConstantsLib.TOKEN_USDC);

        // 100 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.METAVAULT_metaUSD, 100 * 1e6);
        assertEq(price, 100 * usdcPrice, "100 USDC => MetaUSD");

        // 2 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.METAVAULT_metaUSD, 2e6);
        assertEq(price, 2 * usdcPrice, "2 USDC");

        // 0 MetaUSD == 1 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.METAVAULT_metaUSD, 0);
        assertEq(price, usdcPrice, "0 USDC");
    }

    function testGetPriceReversetWS() public view {
        uint price;
        address pool = SonicConstantsLib.METAVAULT_metaS;

        // ---------------------- get amount of MetaS that should be received for the given amount of wS

        // Example:
        // 1 MetaS = $0.3098776
        // 1 wS = $0.3098776
        // 1 MetaS = 1 wS

        // MetaS has 18 decimals, wS has 18 decimals

        // 100 MetaS => wS
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_wS, SonicConstantsLib.METAVAULT_metaS, 100 * 1e18);
        assertEq(price, 100e18, "100 wS => MetaS");

        // 0 MetaUSD == 1 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_wS, SonicConstantsLib.METAVAULT_metaS, 0);
        assertEq(price, 1e18, "0 wS");
    }

    function testGetPriceReverseScUSD() public view {
        uint price;
        address pool = SonicConstantsLib.METAVAULT_metaUSD;

        // ---------------------- get amount of metaUSD that should be received for the given amount of scUSD
        // Example:
        //  1 MetaUSD = $1
        //  1 scUSD = $0.99911831
        //  1 MetaUSD = 1.000882 scUSD

        // MetaUSD has 18 decimals, scUSD has 6 decimals

        (uint scusdPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(SonicConstantsLib.TOKEN_scUSD);

        // 100 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_scUSD, SonicConstantsLib.METAVAULT_metaUSD, 100 * 1e6);
        assertEq(price, 100 * scusdPrice, "100 scUSD => MetaUSD");

        // 2 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_scUSD, SonicConstantsLib.METAVAULT_metaUSD, 2e6);
        assertEq(price, 2 * scusdPrice, "2 scUSD");

        // 0 MetaUSD == 1 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_scUSD, SonicConstantsLib.METAVAULT_metaUSD, 0);
        assertEq(price, scusdPrice, "0 scUSD");
    }
    //endregion ------------------------------------ Get price other tokens in other MetaUSD

    //region ------------------------------------ Internal logic
    function _swap(
        address pool,
        address tokenIn,
        address tokenOut,
        uint amount,
        uint priceImpact
    ) internal returns (uint) {
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
        metaVault.depositAssets(assets, amountsMax, sharesOut * 99 / 100, user);

        vm.roll(block.number + 6);
    }

    function _addAdapter() internal {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new MetaVaultAdapter()));
        MetaVaultAdapter(address(proxy)).init(PLATFORM);
        IPriceReader priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        multisig = IPlatform(PLATFORM).multisig();

        vm.prank(multisig);
        priceReader.addAdapter(address(proxy));

        adapter = MetaVaultAdapter(address(proxy));
    }

    function _dealAndApprove(address user, address spender, address[] memory assets, uint[] memory amounts) internal {
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
