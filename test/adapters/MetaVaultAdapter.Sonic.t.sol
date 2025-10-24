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

contract MetaVaultAdapterTest is SonicSetup {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    bytes32 public _hash;
    MetaVaultAdapter public adapter;
    address public multisig;

    constructor() {
        vm.rollFork(35998179); // Jun-26-2025 11:16:51 AM +UTC
        _init();
        _hash = keccak256(bytes(AmmAdapterIdLib.META_VAULT));

        _addAdapter();
    }

    //region ------------------------------------ Tests for swaps
    function testSwapsMetaUSD100USDC() public {
        _testSwapsMetaUSD(SonicConstantsLib.TOKEN_USDC, 100e6);
    }

    function testSwapsMetaUSD100000USDC() public {
        _testSwapsMetaUSD(SonicConstantsLib.TOKEN_USDC, 100_000e6);
    }

    function testSwapsMetaUSD100scUSD() public {
        _testSwapsMetaUSD(SonicConstantsLib.TOKEN_SCUSD, 100e6);
    }

    function testSwapsMetaUSD100000scUSD() public {
        _testSwapsMetaUSD(SonicConstantsLib.TOKEN_SCUSD, 100_000e6);
    }

    function _testSwapsMetaUSD(address token, uint amount) internal {
        IMetaVault metaVaultUSD = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        uint got;
        address[] memory vaults = metaVaultUSD.vaults();
        assertEq(vaults.length, 2);
        uint i = token == SonicConstantsLib.TOKEN_USDC ? 0 : 1;

        // set up vault for deposit
        _setProportions(metaVaultUSD, i, true);
        assertEq(metaVaultUSD.vaultForDeposit(), vaults[i], "vaultForDeposit mismatch");

        // deposit 100 USDC to MetaVault and get MetaUSD on balance
        deal(token, address(this), amount);
        _depositToMetaVault(metaVaultUSD, amount, address(this));
        uint metaVaultBalance = metaVaultUSD.balanceOf(address(this));

        // set up vault for withdraw
        _setProportions(metaVaultUSD, i, false);
        if (metaVaultUSD.vaultForWithdraw() != vaults[i]) {
            deal(token, address(1), 1_000_000e6);
            _depositToMetaVault(metaVaultUSD, 1_000_000e6, address(1));
        }
        assertEq(metaVaultUSD.vaultForWithdraw(), vaults[i], "vaultForWithdraw mismatch");

        // swap 100 MetaUSD to USDC
        got = _swap(
            SonicConstantsLib.METAVAULT_METAUSD,
            SonicConstantsLib.METAVAULT_METAUSD,
            token,
            metaVaultBalance,
            1_000 // 1% price impact
        );
        vm.roll(block.number + 6);
        assertApproxEqAbs(got, amount, 2, "got all USDC (difference in 2 decimals is allowed)");

        // set up vault for deposit
        _setProportions(metaVaultUSD, i, true);
        assertEq(metaVaultUSD.vaultForDeposit(), vaults[i], "vaultForDeposit mismatch 2");

        // swap 100 USDC to MetaUSD
        got = _swap(
            SonicConstantsLib.METAVAULT_METAUSD,
            token,
            SonicConstantsLib.METAVAULT_METAUSD,
            got,
            1_000 // 1% price impact
        );
        vm.roll(block.number + 6);
        assertLt(_getDiffPercent18(got, metaVaultBalance), 1e10, "got ~ metaVaultBalance back (losses are almost 0)");
    }

    function testSwapsMetaS() public {
        IMetaVault metaVaultS = IMetaVault(SonicConstantsLib.METAVAULT_METAS);

        uint got;
        address[] memory vaults = metaVaultS.vaults();
        assertEq(vaults.length, 1);

        // deposit 100 wS to MetaVault and get MetaS on balance
        deal(SonicConstantsLib.TOKEN_WS, address(this), 100e18);
        _depositToMetaVault(metaVaultS, 100e18, address(this));
        uint metaVaultBalance = metaVaultS.balanceOf(address(this));

        // swap 100 MetaS to wS
        got = _swap(
            SonicConstantsLib.METAVAULT_METAS,
            SonicConstantsLib.METAVAULT_METAS,
            SonicConstantsLib.TOKEN_WS,
            metaVaultBalance,
            1_000 // 1% price impact
        );
        vm.roll(block.number + 6);
        assertApproxEqAbs(got, 100e18, 100, "got all wS back");

        // swap 100 wS to MetaS
        got = _swap(
            SonicConstantsLib.METAVAULT_METAS,
            SonicConstantsLib.TOKEN_WS,
            SonicConstantsLib.METAVAULT_METAS,
            got,
            1_000 // 1% price impact
        );
        vm.roll(block.number + 6);
        assertApproxEqAbs(got, metaVaultBalance, 100, "got all metaS back");
    }

    function testSwapsMetaUsdc() public {
        IMetaVault metaVaultUsdc = IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);

        uint got;
        address[] memory vaults = metaVaultUsdc.vaults();
        assertGt(vaults.length, 2);

        // deposit 100 wS to MetaVault and get MetaS on balance
        deal(SonicConstantsLib.TOKEN_USDC, address(this), 100e6);
        _depositToMetaVault(metaVaultUsdc, 100e6, address(this));
        uint metaVaultBalance = metaVaultUsdc.balanceOf(address(this));

        // swap 100 MetaUSDC to USDC
        got = _swap(
            SonicConstantsLib.METAVAULT_METAUSDC,
            SonicConstantsLib.METAVAULT_METAUSDC,
            SonicConstantsLib.TOKEN_USDC,
            metaVaultBalance,
            1_000 // 1% price impact
        );
        vm.roll(block.number + 6);
        assertEq(got, 100e6, "got all usdc");

        // swap 100 wS to MetaS
        got = _swap(
            SonicConstantsLib.METAVAULT_METAUSDC,
            SonicConstantsLib.TOKEN_USDC,
            SonicConstantsLib.METAVAULT_METAUSDC,
            got,
            1_000 // 1% price impact
        );
        vm.roll(block.number + 6);
        assertEq(got, metaVaultBalance, "got all metaUSDC back");
    }

    function testSwapBadPathIncorectToken() public {
        deal(SonicConstantsLib.TOKEN_USDC, address(this), 100e6);
        /// forge-lint: disable-next-line
        IERC20(SonicConstantsLib.TOKEN_USDC).transfer(address(adapter), 100e6);
        vm.roll(block.number + 6);

        vm.expectRevert(MetaVaultAdapter.IncorrectTokens.selector);
        adapter.swap(
            SonicConstantsLib.METAVAULT_METAS,
            SonicConstantsLib.TOKEN_USDC, // (!) incorrect token IN
            SonicConstantsLib.TOKEN_WS,
            address(this),
            1_000
        );
    }

    //endregion ------------------------------------ Tests for swaps

    //region ------------------------------------ Tests for view functions
    function testAmmAdapterId() public view {
        assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash);
    }

    function testPoolTokens() public view {
        IMetaVault metaVaultUSD = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        address pool = SonicConstantsLib.METAVAULT_METAUSD;
        address[] memory poolTokens = adapter.poolTokens(pool);
        assertEq(poolTokens.length, 3);
        assertEq(poolTokens[0], pool);
        assertEq(poolTokens[1], IMetaVault(metaVaultUSD.vaults()[0]).assets()[0]);
        assertEq(poolTokens[2], IMetaVault(metaVaultUSD.vaults()[1]).assets()[0]);
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
        address pool = SonicConstantsLib.METAVAULT_METAUSD;

        // 1 MetaUSD => aUSDC (not supported token)
        vm.expectRevert();
        adapter.getPrice(pool, SonicConstantsLib.METAVAULT_METAUSD, SonicConstantsLib.TOKEN_AUSDC, 0);

        // 1 USDC => 1 scUSD (there is no MetaUSD)
        vm.expectRevert();
        adapter.getPrice(pool, SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_SCUSD, 0);
    }

    function testIMetaVaultAmmAdapter() public view {
        IMetaVault metaVaultUSD = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        assertEq(adapter.assetForDeposit(SonicConstantsLib.METAVAULT_METAUSD), metaVaultUSD.assetsForDeposit()[0]);
        assertEq(adapter.assetForWithdraw(SonicConstantsLib.METAVAULT_METAUSD), metaVaultUSD.assetsForWithdraw()[0]);
    }

    function testGetTwaPrice() public {
        vm.expectRevert("Not supported");
        adapter.getTwaPrice(address(0), address(0), address(0), 0, 0);
    }

    //endregion ------------------------------------ Tests for view functions

    //region ------------------------------------ Get price of MetaVault in other tokens
    function testGetPriceDirectUSDC() public view {
        uint price;
        address pool = SonicConstantsLib.METAVAULT_METAUSD;

        // ---------------------- get amount of USDC that should be received for the given amount of MetaUSD
        // Example:
        //  1 MetaUSD = $1
        //  1 USDC = $0.99985
        //  1 MetaUSD = 1.000150 USDC

        // MetaUSD has 18 decimals, USDC has 6 decimals

        (uint usdcPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(SonicConstantsLib.TOKEN_USDC);

        // 100 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_METAUSD, SonicConstantsLib.TOKEN_USDC, 100 * 1e18);
        assertEq(price, 1e6 * 100 * 1e18 / usdcPrice, "100 MetaUSD => USDC");

        // 2 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_METAUSD, SonicConstantsLib.TOKEN_USDC, 2e18);
        assertEq(price, 1e6 * 2 * 1e18 / usdcPrice, "2 MetaUSD");

        // 0 MetaUSD == 1 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_METAUSD, SonicConstantsLib.TOKEN_USDC, 0);
        assertEq(price, 1e6 * 1 * 1e18 / usdcPrice, "0 MetaUSD");
    }

    function testGetPriceDirectWS() public view {
        uint price;
        address pool = SonicConstantsLib.METAVAULT_METAS;

        // ---------------------- get amount of wS that should be received for the given amount of MetaUSD

        // Example:
        // 1 MetaS = $0.3098776
        // 1 wS = $0.3098776
        // 1 MetaS = 1 wS

        // MetaS has 18 decimals, wS has 18 decimals

        // 100 MetaS => wS
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_METAS, SonicConstantsLib.TOKEN_WS, 100 * 1e18);
        assertEq(price, 100e18, "100 MetaS => wS");

        // 0 MetaUSD == 1 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_METAS, SonicConstantsLib.TOKEN_WS, 0);
        assertEq(price, 1e18, "0 wS");
    }

    function testGetPriceDirectScUSD() public view {
        uint price;
        address pool = SonicConstantsLib.METAVAULT_METAUSD;

        // ---------------------- get amount of scUSD that should be received for the given amount of MetaUSD
        // Example:
        //  1 MetaUSD = $1
        //  1 scUSD = $0.99911831
        //  1 MetaUSD = 1.000882 scUSD

        // MetaUSD has 18 decimals, scUSD has 6 decimals

        (uint scusdPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(SonicConstantsLib.TOKEN_SCUSD);

        // 100 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_METAUSD, SonicConstantsLib.TOKEN_SCUSD, 100 * 1e18);
        assertEq(price, 1e6 * 100 * 1e18 / scusdPrice, "100 MetaUSD => scUSD");

        // 2 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_METAUSD, SonicConstantsLib.TOKEN_SCUSD, 2e18);
        assertEq(price, 1e6 * 2 * 1e18 / scusdPrice, "2 MetaUSD");

        // 0 MetaUSD == 1 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_METAUSD, SonicConstantsLib.TOKEN_SCUSD, 0);
        assertEq(price, 1e6 * 1 * 1e18 / scusdPrice, "0 MetaUSD");
    }

    function getGetPriceDirectMetaUsdcInUsdc() public view {
        uint price;
        address pool = SonicConstantsLib.METAVAULT_METAUSDC;

        // ---------------------- get amount of USDC that should be received for the given amount of MetaUSD
        // Example:
        //  1 MetaUSDC = $0.99985
        //  1 USDC = $0.99985
        //  1 MetaUSDC = 1.0 USDC

        // MetaUSD has 18 decimals, USDC has 6 decimals

        (uint usdcPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(SonicConstantsLib.TOKEN_USDC);

        // 100 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_METAUSDC, SonicConstantsLib.TOKEN_USDC, 100 * 1e18);
        assertEq(price, 100e6, "100 MetaUSDC => USDC");

        // 2 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_METAUSDC, SonicConstantsLib.TOKEN_USDC, 2e18);
        assertEq(price, 2e6, "2 MetaUSDC");

        // 0 MetaUSD == 1 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.METAVAULT_METAUSDC, SonicConstantsLib.TOKEN_USDC, 0);
        assertEq(price, 1e6 / usdcPrice, "0 MetaUSD");
    }

    //endregion ------------------------------------ Get price of MetaVault in other tokens

    //region ------------------------------------ Get price of other tokens in MetaVault
    function testGetPriceReverseUSDC() public view {
        uint price;
        address pool = SonicConstantsLib.METAVAULT_METAUSD;

        // ---------------------- get amount of MetaUSD that should be received for the given amount of USDC
        // Example:
        //  1 MetaUSD = $1
        //  1 USDC = $0.99985
        //  1 MetaUSD = 1.000150 USDC

        // MetaUSD has 18 decimals, USDC has 6 decimals

        (uint usdcPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(SonicConstantsLib.TOKEN_USDC);

        // 100 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.METAVAULT_METAUSD, 100 * 1e6);
        assertEq(price, 100 * usdcPrice, "100 USDC => MetaUSD");

        // 2 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.METAVAULT_METAUSD, 2e6);
        assertEq(price, 2 * usdcPrice, "2 USDC");

        // 0 MetaUSD == 1 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.METAVAULT_METAUSD, 0);
        assertEq(price, usdcPrice, "0 USDC");
    }

    function testGetPriceReversetWS() public view {
        uint price;
        address pool = SonicConstantsLib.METAVAULT_METAS;

        // ---------------------- get amount of MetaS that should be received for the given amount of wS

        // Example:
        // 1 MetaS = $0.3098776
        // 1 wS = $0.3098776
        // 1 MetaS = 1 wS

        // MetaS has 18 decimals, wS has 18 decimals

        // 100 MetaS => wS
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_WS, SonicConstantsLib.METAVAULT_METAS, 100 * 1e18);
        assertEq(price, 100e18, "100 wS => MetaS");

        // 0 MetaUSD == 1 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_WS, SonicConstantsLib.METAVAULT_METAS, 0);
        assertEq(price, 1e18, "0 wS");
    }

    function testGetPriceReverseScUSD() public view {
        uint price;
        address pool = SonicConstantsLib.METAVAULT_METAUSD;

        // ---------------------- get amount of metaUSD that should be received for the given amount of scUSD
        // Example:
        //  1 MetaUSD = $1
        //  1 scUSD = $0.99911831
        //  1 MetaUSD = 1.000882 scUSD

        // MetaUSD has 18 decimals, scUSD has 6 decimals

        (uint scusdPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(SonicConstantsLib.TOKEN_SCUSD);

        // 100 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_SCUSD, SonicConstantsLib.METAVAULT_METAUSD, 100 * 1e6);
        assertEq(price, 100 * scusdPrice, "100 scUSD => MetaUSD");

        // 2 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_SCUSD, SonicConstantsLib.METAVAULT_METAUSD, 2e6);
        assertEq(price, 2 * scusdPrice, "2 scUSD");

        // 0 MetaUSD == 1 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_SCUSD, SonicConstantsLib.METAVAULT_METAUSD, 0);
        assertEq(price, scusdPrice, "0 scUSD");
    }

    function testGetPriceReverseUsdcToMetaUsdc() public view {
        uint price;
        address pool = SonicConstantsLib.METAVAULT_METAUSDC;

        // ---------------------- get amount of MetaUSD that should be received for the given amount of USDC
        // Example:
        //  1 MetaUSDC = $0.99985
        //  1 USDC = $0.99985
        //  1 MetaUSDC = 1 USDC

        // MetaUSD has 18 decimals, USDC has 6 decimals

        // 100 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.METAVAULT_METAUSDC, 100 * 1e6);
        assertEq(price, 100e18, "100 USDC => MetaUSDC");

        // 2 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.METAVAULT_METAUSDC, 2e6);
        assertEq(price, 2e18, "2 USDC");

        // 0 MetaUSD == 1 MetaUSD => USDC
        price = adapter.getPrice(pool, SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.METAVAULT_METAUSDC, 0);
        assertEq(price, 1e18, "0 USDC");
    }

    //endregion ------------------------------------ Get price of other tokens in MetaVault

    //region ------------------------------------ Internal logic
    function _swap(
        address pool,
        address tokenIn,
        address tokenOut,
        uint amount,
        uint priceImpact
    ) internal returns (uint) {
        /// forge-lint: disable-next-line
        IERC20(tokenIn).transfer(address(adapter), amount);
        vm.roll(block.number + 6);

        uint balanceWas = IERC20(tokenOut).balanceOf(address(this));
        adapter.swap(pool, tokenIn, tokenOut, address(this), priceImpact);
        return IERC20(tokenOut).balanceOf(address(this)) - balanceWas;
    }

    //endregion ------------------------------------ Internal logic

    //region ------------------------------------ Helper functions
    function _depositToMetaVault(IMetaVault metaVault_, uint amount, address user) internal {
        address[] memory assets = metaVault_.assetsForDeposit();
        uint[] memory amountsMax = new uint[](1);
        amountsMax[0] = amount;

        _dealAndApprove(user, address(metaVault_), assets, amountsMax);

        (,, uint valueOut) = metaVault_.previewDepositAssets(assets, amountsMax);

        vm.prank(user);
        metaVault_.depositAssets(assets, amountsMax, valueOut * 99 / 100, user);

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

    function _setProportions(IMetaVault metaVault_, uint index, bool toDeposit) internal {
        uint indexOpposite = index == 0 ? 1 : 0;
        uint[] memory props = metaVault_.targetProportions();
        uint[] memory current = metaVault_.currentProportions();

        if (toDeposit) {
            props[index] = 1e18;
            props[indexOpposite] = 0;
        } else {
            props[index] = 1e18 - current[indexOpposite];
            props[indexOpposite] = current[indexOpposite];
        }

        vm.prank(multisig);
        metaVault_.setTargetProportions(props);

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
