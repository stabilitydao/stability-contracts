// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Test, console} from "forge-std/Test.sol";
import {MockSetup} from "../base/MockSetup.sol";
import {Allocator} from "../../src/tokenomics/Allocator.sol";
import {Sale} from "../../src/tokenomics/Sale.sol";
import {SaleReceiptToken} from "../../src/tokenomics/SaleReceiptToken.sol";
import {STBL} from "../../src/tokenomics/STBL.sol";
import {Vesting} from "../../src/tokenomics/Vesting.sol";

contract LaunchTest is Test, MockSetup {
    uint public constant SALE_PRICE = 125000;
    uint64 public constant SALE_START = 1741132800; // Wed Mar 05 2025 00:00:00 GMT+0000
    uint64 public constant SALE_END = 1741564800; // Mon Mar 10 2025 00:00:00 GMT+0000
    uint64 public constant TGE = 1741737600; // Wed Mar 12 2025 00:00:00 GMT+0000
    uint64 public constant ONE_YEAR = 365 days;
    uint64 public constant HALF_YEAR = ONE_YEAR / 2;
    uint64 public constant FOUR_YEARS = 4 * ONE_YEAR;

    Allocator public allocator;
    address public stbl;
    Sale public sale;
    address public investors;
    address public foundation;
    address public community;
    address public team;
    address public receiptToken;

    function test_launch() public {
        _deploySale();

        // test Sale
        deal(address(tokenB), address(1), 150_000 * 1e6); // $150k
        deal(address(tokenB), address(2), 50_000 * 1e6); // $50k
        deal(address(tokenB), address(3), 10_000 * 1e6); // $10k
        deal(address(tokenB), address(4), 60_000 * 1e6); // $60k
        deal(address(tokenB), address(5), 60_000 * 1e6); // $60k
        deal(address(tokenB), address(6), 60_000 * 1e6); // $60k
        deal(address(tokenB), address(7), 60_000 * 1e6); // $60k
        deal(address(tokenB), address(8), 60_000 * 1e6); // $60k
        deal(address(tokenB), address(9), 60_000 * 1e6); // $60k
        deal(address(tokenB), address(10), 60_000 * 1e6); // $60k
        deal(address(tokenB), address(11), 60_000 * 1e6); // $60k

        // sale not started
        vm.expectRevert("Sale is not started yet");
        sale.buy(1);

        // warp time
        vm.warp(SALE_START);

        // small amount is zero amount
        vm.expectRevert("Zero amount");
        sale.buy(1);

        // try to buy 10.0 STBL without approve
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, sale, 0, 1250000));
        sale.buy(10 * 1e18);

        // USER address(1) buy 100k + 300k STBL
        vm.startPrank(address(1));
        tokenB.approve(address(sale), type(uint).max);
        sale.buy(100_000 * 1e18);
        assertEq(tokenB.balanceOf(platform.multisig()), 100_000 * 1e18 * SALE_PRICE / 1e18);
        sale.buy(300_000 * 1e18);
        assertEq(tokenB.balanceOf(platform.multisig()), 400_000 * 1e18 * SALE_PRICE / 1e18);
        vm.expectRevert("Too much for user");
        sale.buy(1);
        assertEq(IERC20(receiptToken).balanceOf(address(1)), 400_000 * 1e18);
        uint spent = 400_000 * 1e18 * SALE_PRICE / 1e18; // $50k
        assertEq(tokenB.balanceOf(address(1)), 150_000 * 1e6 - spent);
        vm.stopPrank();
        // //////////////

        vm.startPrank(address(2));
        tokenB.approve(address(sale), type(uint).max);
        sale.buy(400_000 * 1e18);
        vm.stopPrank();

        vm.startPrank(address(3));
        tokenB.approve(address(sale), type(uint).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(3), 10_000 * 1e6, 50_000 * 1e6
            )
        );
        sale.buy(400_000 * 1e18);
        sale.buy(80_000 * 1e18);
        vm.stopPrank();

        vm.startPrank(address(4));
        tokenB.approve(address(sale), type(uint).max);
        sale.buy(400_000 * 1e18);
        vm.stopPrank();

        vm.startPrank(address(5));
        tokenB.approve(address(sale), type(uint).max);
        sale.buy(400_000 * 1e18);
        vm.stopPrank();

        vm.startPrank(address(6));
        tokenB.approve(address(sale), type(uint).max);
        sale.buy(400_000 * 1e18);
        vm.stopPrank();

        vm.startPrank(address(7));
        tokenB.approve(address(sale), type(uint).max);
        sale.buy(400_000 * 1e18);
        vm.stopPrank();

        vm.startPrank(address(8));
        tokenB.approve(address(sale), type(uint).max);
        sale.buy(400_000 * 1e18);
        vm.stopPrank();

        vm.startPrank(address(9));
        tokenB.approve(address(sale), type(uint).max);
        sale.buy(400_000 * 1e18);
        vm.stopPrank();

        vm.startPrank(address(10));
        tokenB.approve(address(sale), type(uint).max);
        sale.buy(400_000 * 1e18);
        vm.stopPrank();

        uint remaining = sale.ALLOCATION_SALE() - sale.sold();
        assertEq(remaining, 320_000 * 1e18);

        vm.startPrank(address(11));
        tokenB.approve(address(sale), type(uint).max);
        vm.expectRevert("Too much");
        sale.buy(remaining + 1);
        sale.buy(remaining);
        vm.expectRevert("Too much");
        sale.buy(1);
        vm.warp(SALE_END + 1);
        vm.expectRevert("Sale ended");
        sale.buy(1);
        vm.stopPrank();

        assertEq(IERC20(receiptToken).totalSupply(), sale.ALLOCATION_SALE());

        // try transfer
        vm.startPrank(address(11));
        vm.expectRevert("Not transferable");
        IERC20(receiptToken).transfer(address(1), 1);
        vm.stopPrank();

        // DEPLOY STBL TOKEN AND ALLOCATE
        _deploy();

        // check revert of not operator tries to allocate
        vm.prank(address(10));
        vm.expectRevert("denied");
        allocator.allocate(stbl, address(sale), investors, foundation, community, team);

        // allocate STBL to contracts
        allocator.allocate(stbl, address(sale), investors, foundation, community, team);

        // check allocations
        assertEq(IERC20(stbl).balanceOf(address(allocator)), 0);
        assertEq(
            IERC20(stbl).balanceOf(platform.multisig()),
            allocator.ALLOCATION_LIQUIDITY() + allocator.ALLOCATION_COMMUNITY_UNLOCKED()
        );
        assertEq(IERC20(stbl).balanceOf(address(sale)), allocator.ALLOCATION_SALE());
        assertEq(IERC20(stbl).balanceOf(investors), allocator.ALLOCATION_INVESTORS());
        assertEq(IERC20(stbl).balanceOf(foundation), allocator.ALLOCATION_FOUNDATION());
        assertEq(IERC20(stbl).balanceOf(community), allocator.ALLOCATION_COMMUNITY());
        assertEq(IERC20(stbl).balanceOf(team), allocator.ALLOCATION_TEAM());

        vm.expectRevert("incorrect supply");
        sale.setupToken(address(tokenB));

        vm.expectRevert("Wait for TGE");
        sale.burnNotSold();

        // setup STBL address for Sale contract
        sale.setupToken(stbl);

        vm.expectRevert("already");
        sale.setupToken(stbl);

        // claim
        vm.startPrank(address(11));
        vm.expectRevert("Wait for TGE");
        sale.claim();
        vm.warp(TGE);
        sale.claim();
        assertEq(IERC20(receiptToken).totalSupply(), sale.ALLOCATION_SALE() - remaining);
        assertEq(IERC20(stbl).balanceOf(address(11)), remaining);
        vm.expectRevert("You dont have not claimed tokens");
        sale.claim();
        vm.stopPrank();

        // all sold
        vm.expectRevert("All sold");
        sale.burnNotSold();
    }

    function test_partially_sold() public {
        _deploySale();

        sale.setupDates(SALE_START, SALE_END, TGE - 1);

        vm.warp(SALE_START);

        deal(address(tokenB), address(1), 150_000 * 1e6); // $150k

        vm.startPrank(address(1));
        tokenB.approve(address(sale), type(uint).max);
        sale.buy(100_000 * 1e18);
        vm.stopPrank();

        _deploy();
        allocator.allocate(stbl, address(sale), investors, foundation, community, team);

        sale.setupToken(stbl);

        sale.setupDates(SALE_START, SALE_END, TGE - 1);

        vm.warp(TGE);

        vm.expectRevert("Cant change");
        sale.setupDates(SALE_START, SALE_END, TGE - 1);

        vm.startPrank(address(1));
        sale.claim();
        vm.stopPrank();

        sale.burnNotSold();
    }

    function test_vesting() public {
        _deploySale();
        _deploy();
        allocator.allocate(stbl, address(sale), investors, foundation, community, team);

        Vesting v = Vesting(investors);
        vm.expectRevert("beneficiary is not set yet");
        v.release();

        v.delayStart(v.start() + 1);

        vm.prank(address(10));
        vm.expectRevert("denied");
        v.setBeneficiary(address(100));

        v.setBeneficiary(address(100));

        vm.expectRevert("Zero amount");
        v.release();

        vm.warp(v.start());
        vm.expectRevert("Zero amount");
        v.release();

        uint balanceWas = IERC20(stbl).balanceOf(address(v));

        vm.warp(v.start() + 3600);
        v.release();
        uint got = balanceWas - IERC20(stbl).balanceOf(address(v));
        assertGt(got, 0);

        vm.warp(v.start() + v.duration());
        v.release();
        got = balanceWas - IERC20(stbl).balanceOf(address(v));
        assertEq(got, allocator.ALLOCATION_INVESTORS());
        assertEq(got, IERC20(stbl).balanceOf(address(100)));

        vm.expectRevert("Zero amount");
        v.release();

        assertEq(v.releasable(), 0);
        assertEq(v.vestedAmount(uint64(block.timestamp)), allocator.ALLOCATION_INVESTORS());
        assertEq(v.end(), v.start() + v.duration());

        vm.expectRevert("denied");
        v.delayStart(1);

        v = Vesting(team);
        v.delayStart(uint64(block.timestamp));
        v.setBeneficiary(address(200));
        vm.warp(block.timestamp + 1 days);
        v.release();
        got = IERC20(stbl).balanceOf(address(200));
        assertGt(got, 13.6e21);
        assertLt(got, 13.7e21);
        vm.warp(v.end());
        v.release();
        got = IERC20(stbl).balanceOf(address(200));
        assertEq(got, allocator.ALLOCATION_TEAM());
    }

    function _deploySale() internal {
        // deploy Sale
        sale = new Sale(
            address(platform),
            address(tokenB),
            SALE_PRICE, // $0.125
            SALE_START,
            SALE_END,
            TGE
        );

        // deploy receipt token
        receiptToken = address(new SaleReceiptToken(address(sale), "STBL Sale Receipt", "saleSTBL"));

        // check revert of not operator tries to setup Sale contract
        vm.prank(address(10));
        vm.expectRevert("denied");
        sale.setupReceiptToken(receiptToken);

        // setup Sale contract
        sale.setupReceiptToken(receiptToken);

        vm.expectRevert("already");
        sale.setupReceiptToken(receiptToken);
    }

    function _deploy() internal {
        // deploy Allocator
        allocator = new Allocator(address(platform));

        // check revert allocate without tokens
        vm.expectRevert("error");
        allocator.allocate(address(tokenA), address(0), address(0), address(0), address(0), address(0));

        // deploy STBL
        stbl = address(new STBL(address(allocator)));

        // deploy vesting
        investors = address(new Vesting(address(platform), stbl, "Investors", ONE_YEAR, TGE + HALF_YEAR));
        foundation = address(new Vesting(address(platform), stbl, "Foundation", FOUR_YEARS, TGE + HALF_YEAR));
        community = address(new Vesting(address(platform), stbl, "Community", FOUR_YEARS, TGE + HALF_YEAR));
        team = address(new Vesting(address(platform), stbl, "Team", FOUR_YEARS, TGE + HALF_YEAR));
    }
}
