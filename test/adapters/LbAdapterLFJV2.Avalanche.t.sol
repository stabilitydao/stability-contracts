// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {LbAdapterLFJV2} from "../../src/adapters/LbAdapterLFJV2.sol";
import {AvalancheSetup} from "../base/chains/AvalancheSetup.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";

contract LbAdapterLFJV2Test is AvalancheSetup {
    using SafeERC20 for IERC20;

    uint public constant FORK_BLOCK_C_CHAIN = 75107760; // Jan-05-2026 11:44:52 AM +UTC

    address public constant PLATFORM = AvalancheConstantsLib.PLATFORM;

    bytes32 public _hash;
    LbAdapterLFJV2 public adapter;
    address public multisig;

    struct State {
        uint adapterBalanceAvUSD;
        uint adapterBalanceStakedAvUSD;
        uint userBalanceAvUSD;
        uint userBalanceStakedAvUSD;
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("AVALANCHE_RPC_URL"), FORK_BLOCK_C_CHAIN));
        _hash = keccak256(bytes(AmmAdapterIdLib.LBLFJ_V2));

        _addAdapter();
    }

    //region ------------------------------------ Tests for view functions
    function testAmmAdapterId() public view {
        assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash);
    }

    function testPoolTokens() public view {
        address[] memory poolTokens = adapter.poolTokens(AvalancheConstantsLib.LFJ_LBPAIR_savUSDC_avUSD);
        assertEq(poolTokens.length, 2);
        assertEq(poolTokens[0], AvalancheConstantsLib.TOKEN_savUSD);
        assertEq(poolTokens[1], AvalancheConstantsLib.TOKEN_avUSD);
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

    function testGetPriceDirectBadPaths() public view {
        address pool = AvalancheConstantsLib.LFJ_LBPAIR_savUSDC_avUSD;

        // --------------------- Incorrect tokens
        assertEq(
            adapter.getPrice(pool, AvalancheConstantsLib.TOKEN_savUSD, AvalancheConstantsLib.TOKEN_USDC, 0),
            0,
            "wrong token out"
        );
        assertEq(
            adapter.getPrice(pool, AvalancheConstantsLib.TOKEN_USDC, AvalancheConstantsLib.TOKEN_savUSD, 0),
            0,
            "wrong token in"
        );

        // --------------------- InsufficientOutputAmount
        try adapter.getPrice(
            pool, AvalancheConstantsLib.TOKEN_savUSD, AvalancheConstantsLib.TOKEN_avUSD, 1e30
        ) returns (
            uint
        ) {
            assertTrue(false, "getPrice didn't revert with InsufficientOutputAmount");
        } catch (bytes memory reason) {
            assertTrue(reason.length >= 4, "revert reason too short");
            bytes4 receivedSelector;
            assembly {
                receivedSelector := mload(add(reason, 32))
            }
            assertEq(receivedSelector, LbAdapterLFJV2.InsufficientOutputAmount.selector);
        }
    }

    function testGetTwaPrice() public {
        vm.expectRevert("Not supported");
        adapter.getTwaPrice(address(0), address(0), address(0), 0, 0);
    }

    //endregion ------------------------------------ Tests for view functions

    //region ------------------------------------ Tests for swaps
    function testStakeAvUsd107() public {
        _testStakeAvUSD(107e18);
    }

    function testStakeAvUsd0() public {
        _testStakeAvUSD(0);
    }

    function testSwapBadPaths() public {
        deal(AvalancheConstantsLib.TOKEN_savUSD, address(address(adapter)), 1e18);
        deal(AvalancheConstantsLib.TOKEN_avUSD, address(address(adapter)), 1e18);

        // --------------------- Incorrect tokens
        vm.expectRevert(LbAdapterLFJV2.IncorrectTokens.selector);
        adapter.swap(
            AvalancheConstantsLib.LFJ_LBPAIR_savUSDC_avUSD,
            AvalancheConstantsLib.TOKEN_savUSD,
            AvalancheConstantsLib.TOKEN_USDC,
            address(this),
            1_000
        );

        vm.expectRevert(LbAdapterLFJV2.IncorrectTokens.selector);
        adapter.swap(
            AvalancheConstantsLib.LFJ_LBPAIR_savUSDC_avUSD,
            AvalancheConstantsLib.TOKEN_USDC,
            AvalancheConstantsLib.TOKEN_savUSD,
            address(this),
            1_000
        );

        // --------------------- InsufficientOutputAmount
        deal(AvalancheConstantsLib.TOKEN_avUSD, address(address(adapter)), 1e30);

        try adapter.swap(
            AvalancheConstantsLib.LFJ_LBPAIR_savUSDC_avUSD,
            AvalancheConstantsLib.TOKEN_avUSD,
            AvalancheConstantsLib.TOKEN_savUSD,
            address(this),
            1e30
        ) {
            assertTrue(false, "swap didn't revert with InsufficientOutputAmount");
        } catch (bytes memory reason) {
            assertTrue(reason.length >= 4, "revert reason too short");
            bytes4 receivedSelector;
            assembly {
                receivedSelector := mload(add(reason, 32))
            }
            assertEq(receivedSelector, LbAdapterLFJV2.InsufficientOutputAmount.selector);
        }
    }

    //endregion ------------------------------------ Tests for swaps

    //region ------------------------------------ Tests implementation
    function _testStakeAvUSD(uint amount) internal {
        deal(AvalancheConstantsLib.TOKEN_avUSD, address(address(this)), amount == 0 ? 1e18 : amount);

        // --------------------- swap avUSD to savUSD
        uint expectedAmount = adapter.getPrice(
            AvalancheConstantsLib.LFJ_LBPAIR_savUSDC_avUSD,
            AvalancheConstantsLib.TOKEN_avUSD,
            AvalancheConstantsLib.TOKEN_savUSD,
            amount
        );
        State memory state0 = getState();

        vm.prank(address(this));
        IERC20(AvalancheConstantsLib.TOKEN_avUSD).safeTransfer(address(adapter), amount == 0 ? 1e18 : amount);

        adapter.swap(
            AvalancheConstantsLib.LFJ_LBPAIR_savUSDC_avUSD,
            AvalancheConstantsLib.TOKEN_avUSD,
            AvalancheConstantsLib.TOKEN_savUSD,
            address(this),
            1_000
        );
        State memory state1 = getState();

        assertApproxEqAbs(
            state1.userBalanceStakedAvUSD - state0.userBalanceStakedAvUSD,
            expectedAmount,
            expectedAmount / 100_000,
            "expected staked amount"
        );
        assertEq(state1.userBalanceAvUSD, 0, "all avUSD spent");
        assertEq(state1.adapterBalanceAvUSD, 0, "adapter avUSD balance");
        assertEq(state1.adapterBalanceStakedAvUSD, 0, "adapter savUSD balance");

        // --------------------- swap savUSD to avUSD
        expectedAmount = adapter.getPrice(
            AvalancheConstantsLib.LFJ_LBPAIR_savUSDC_avUSD,
            AvalancheConstantsLib.TOKEN_savUSD,
            AvalancheConstantsLib.TOKEN_avUSD,
            state1.userBalanceStakedAvUSD
        );

        IERC20(AvalancheConstantsLib.TOKEN_savUSD).safeTransfer(address(adapter), state1.userBalanceStakedAvUSD);
        adapter.swap(
            AvalancheConstantsLib.LFJ_LBPAIR_savUSDC_avUSD,
            AvalancheConstantsLib.TOKEN_savUSD,
            AvalancheConstantsLib.TOKEN_avUSD,
            address(this),
            1_000
        );

        State memory state2 = getState();
        assertApproxEqAbs(
            state2.userBalanceAvUSD - state1.userBalanceAvUSD,
            expectedAmount,
            expectedAmount / 100_000,
            "expected amount of BUSD"
        );
        assertEq(state2.userBalanceStakedAvUSD, 0, "all Staked avUSD spent");
        assertEq(state2.adapterBalanceAvUSD, 0, "adapter avUSD balance");
        assertEq(state2.adapterBalanceStakedAvUSD, 0, "adapter savUSD balance");

        assertApproxEqRel(
            state2.userBalanceAvUSD, state0.userBalanceAvUSD, 1e18 / 1000, "initial amount without fees back"
        );
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
        state.adapterBalanceAvUSD = IERC20(AvalancheConstantsLib.TOKEN_avUSD).balanceOf(address(adapter));
        state.adapterBalanceStakedAvUSD = IERC20(AvalancheConstantsLib.TOKEN_savUSD).balanceOf(address(adapter));
        state.userBalanceAvUSD = IERC20(AvalancheConstantsLib.TOKEN_avUSD).balanceOf(address(this));
        state.userBalanceStakedAvUSD = IERC20(AvalancheConstantsLib.TOKEN_savUSD).balanceOf(address(this));
        return state;
    }

    function _addAdapter() internal {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new LbAdapterLFJV2()));
        LbAdapterLFJV2(address(proxy)).init(PLATFORM);
        IPriceReader priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        multisig = IPlatform(PLATFORM).multisig();

        vm.prank(multisig);
        priceReader.addAdapter(address(proxy));

        adapter = LbAdapterLFJV2(address(proxy));
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
