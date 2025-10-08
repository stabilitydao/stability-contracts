// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BrunchAdapter} from "../../src/adapters/BrunchAdapter.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SonicSetup, SonicConstantsLib, IERC20} from "../base/chains/SonicSetup.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IStakedBUSD} from "../../src/integrations/brunch/IStakedBUSD.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {console} from "forge-std/console.sol";

contract BrunchAdapterTest is SonicSetup {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;

    bytes32 public _hash;
    BrunchAdapter public adapter;
    address public multisig;

    struct State {
        uint adapterBalanceBUSD;
        uint adapterBalanceStakedBUSD;
        uint userBalanceBUSD;
        uint userBalanceStakedBUSD;
        uint exchangeRate;
    }

    constructor() {
        vm.rollFork(49631613); // Oct-07-2025 10:54:07 AM +UTC
        _init();
        _hash = keccak256(bytes(AmmAdapterIdLib.BRUNCH));

        _addAdapter();
    }

    //region ------------------------------------ Tests for view functions
    function testAmmAdapterId() public view {
        assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash);
    }

    function testPoolTokens() public view {
        address[] memory poolTokens = adapter.poolTokens(SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD);
        assertEq(poolTokens.length, 2);
        assertEq(poolTokens[0], SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD);
        assertEq(poolTokens[1], SonicConstantsLib.TOKEN_BRUNCH_USD);
    }

    function testNotSupportedMethods() public {
        vm.expectRevert("Not supported");
        adapter.getLiquidityForAmounts(address(0), new uint[](2));

        vm.expectRevert("Not supported");
        adapter.getProportions(address(0));
    }

    function testIERC165() public view {
        assertEq(adapter.supportsInterface(type(IAmmAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IERC165).interfaceId), true);
    }

    function testGetPriceDirectBadPaths() public {
        address pool = SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD;

        vm.expectRevert();
        adapter.getPrice(pool, SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD, SonicConstantsLib.TOKEN_AUSDC, 0);

        vm.expectRevert();
        adapter.getPrice(pool, SonicConstantsLib.TOKEN_AUSDC, SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD, 0);
    }
    //endregion ------------------------------------ Tests for view functions

    //region ------------------------------------ Tests for swaps
    function testStakeBrunchUsd107() public {
        _testStakeBrunchUSD(107e18);
    }

    function testStakeBrunchUsd0() public {
        _testStakeBrunchUSD(0);
    }

    function testStakeBrunchBadPaths() public {
        deal(SonicConstantsLib.TOKEN_BRUNCH_USD, address(address(adapter)), 1e18);
        deal(SonicConstantsLib.TOKEN_USDC, address(address(adapter)), 1e6);

        vm.expectRevert(BrunchAdapter.IncorrectTokens.selector);
        adapter.swap(
            SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD,
            SonicConstantsLib.TOKEN_BRUNCH_USD,
            SonicConstantsLib.TOKEN_USDC,
            address(this),
            1_000
        );

        vm.expectRevert(BrunchAdapter.IncorrectTokens.selector);
        adapter.swap(
            SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD,
            SonicConstantsLib.TOKEN_USDC,
            SonicConstantsLib.TOKEN_BRUNCH_USD,
            address(this),
            1_000
        );
    }
    //endregion ------------------------------------ Tests for swaps

    //region ------------------------------------ Tests implementation
    function _testStakeBrunchUSD(uint amount) internal {
        deal(SonicConstantsLib.TOKEN_BRUNCH_USD, address(address(this)), amount == 0 ? 1e18 : amount);

        // --------------------- swap BUSD to stBUSD
        uint expectedAmount = adapter.getPrice(
            SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD,
            SonicConstantsLib.TOKEN_BRUNCH_USD,
            SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD,
            amount
        );
        State memory state0 = getState();

        vm.prank(address(this));
        IERC20(SonicConstantsLib.TOKEN_BRUNCH_USD).transfer(address(adapter), amount == 0 ? 1e18 : amount);

        adapter.swap(
            SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD,
            SonicConstantsLib.TOKEN_BRUNCH_USD,
            SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD,
            address(this),
            1_000
        );
        State memory state1 = getState();

        assertApproxEqAbs(
            state1.userBalanceStakedBUSD - state0.userBalanceStakedBUSD,
            expectedAmount,
            expectedAmount / 100_000,
            "expected amount of stBUSD"
        );
        assertEq(state1.userBalanceBUSD, 0, "all BUSD spent");
        assertEq(state1.adapterBalanceBUSD, 0, "adapter BUSD balance");
        assertEq(state1.adapterBalanceStakedBUSD, 0, "adapter stBUSD balance");

        // --------------------- swap stBUSD to BUSD
        expectedAmount = adapter.getPrice(
            SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD,
            SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD,
            SonicConstantsLib.TOKEN_BRUNCH_USD,
            state1.userBalanceStakedBUSD
        );

        IERC20(SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD).transfer(address(adapter), state1.userBalanceStakedBUSD);
        adapter.swap(
            SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD,
            SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD,
            SonicConstantsLib.TOKEN_BRUNCH_USD,
            address(this),
            1_000
        );

        State memory state2 = getState();
        assertApproxEqAbs(
            state2.userBalanceBUSD - state1.userBalanceBUSD,
            expectedAmount,
            expectedAmount / 100_000,
            "expected amount of BUSD"
        );
        assertEq(state2.userBalanceStakedBUSD, 0, "all Staked BUSD spent");
        assertEq(state2.adapterBalanceBUSD, 0, "adapter BUSD balance");
        assertEq(state2.adapterBalanceStakedBUSD, 0, "adapter stBUSD balance");

        assertApproxEqAbs(state2.userBalanceBUSD, state0.userBalanceBUSD, 1, "all BUSD back");
    }

    //endregion ------------------------------------ Tests implementation

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
    function getState() internal view returns (State memory state) {
        state.adapterBalanceBUSD = IERC20(SonicConstantsLib.TOKEN_BRUNCH_USD).balanceOf(address(adapter));
        state.adapterBalanceStakedBUSD = IERC20(SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD).balanceOf(address(adapter));
        state.userBalanceBUSD = IERC20(SonicConstantsLib.TOKEN_BRUNCH_USD).balanceOf(address(this));
        state.userBalanceStakedBUSD = IERC20(SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD).balanceOf(address(this));
        state.exchangeRate = IStakedBUSD(SonicConstantsLib.TOKEN_STAKED_BRUNCH_USD).exchangeRateStored();
        return state;
    }

    function _addAdapter() internal {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BrunchAdapter()));
        BrunchAdapter(address(proxy)).init(PLATFORM);
        IPriceReader priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        multisig = IPlatform(PLATFORM).multisig();

        vm.prank(multisig);
        priceReader.addAdapter(address(proxy));

        adapter = BrunchAdapter(address(proxy));
    }

    function _dealAndApprove(address user, address spender, address[] memory assets, uint[] memory amounts) internal {
        for (uint j; j < assets.length; ++j) {
            deal(assets[j], user, amounts[j]);
            vm.prank(user);
            IERC20(assets[j]).approve(spender, amounts[j]);
        }
    }
    //endregion ------------------------------------ Helper functions
}
